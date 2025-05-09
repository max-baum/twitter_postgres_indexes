# Twitter Postgres Indexes

<img align="right" src=the-sql-queries.jpg width=200px >

This is a continuation of the [parallel twitter in postgres assignment](https://github.com/mikeizbicki/twitter_postgres_parallel).

In the last assignments, you learned how to insert data quickly into the database.
Now your goal will be to make the SELECT queries fast.

For this assignment, we will work with 10 days of twitter data, about 31 million tweets.
This is enough data that indexes will dramatically improve query times,
but you won't have to wait days to create each index and see if it works correctly.

> **WARNING:**
> This assignment can put lots of load on the lambda server.
> Depending on the lambda server's current load, you may have to wait up to 12 hours for individual CREATE INDEX commands to run.
> If you wait until the last minute,
> you are very likely to not finish on time.
> THERE WILL BE NO EXTENSIONS FOR THIS ASSIGNMENT.

## Step 0: Setup

1. Fork this repo, and clone your fork onto the lambda server.

1. Remove the volumes you created in your previous assignment by first bringing down/stopping all containers, then pruning the volumes:
   ```
   $ docker stop $(docker ps -q)
   $ docker rm $(docker ps -qa)
   $ docker volume prune --all
   ```
   This will free up a lot of disk space and other resources.

   > **WARNING:**
   > Your lambda server resources have been carefully allocated so that you can complete this assignment without exceeding resource limitations.
   > If you still have docker "stuff" from past assignments using resources,
   > however, you are likely to run out of resources and get inscrutable error messages.

1. Modify the `docker-compose.yml` file so that the ports for each of the services are distinct.

    Bring up the docker containers and ensure there are no errors
    ```
    $ docker-compose up -d --build
    ```

1. Notice that the `docker-compose.yml` file uses a [bind mount](https://docs.docker.com/storage/bind-mounts/) into your `$HOME/bigdata` directory whereas all of our previous assignments stored data into a [named volume](https://docs.docker.com/storage/volumes/).

    This is necessary because in this assignment, you will be creating approximately 100GB worth of databases.
    This won't fit in your home folder on the NVME drive (10G limit), and so you must put it into the HDD drives (250G limit).

    This will create a few problems for you.
    In particular, notice that the permissions of the created folders are rather weird:
    ```
    $ cd ~/bigdata
    $ ls -l
    total 12
    drwx------+ 19  4688518 students 4096 Apr  8 15:19 pg_denormalized
    drwx------+ 19  4688518 students 4096 Apr  8 15:19 pg_normalized_batch
    ```
    If you run the commands above, you will have different UIDs.
    These are the UID of the `root` user of your docker container.
    Since you are not currently logged in as that user,
    you will not be able to manipulate these files directly.

    The main way this is a problem is if you need to reset/delete your volumes for some reason.
    When using a named mount, this was easy to do with the
    ```
    $ docker volume prune
    ```
    command.
    This command will not work for bind mounts, however.
    Whenever you use a bind mount, everything must be done manually.
    These mounts have more flexibility (we can store the data wherever we want), but they become much more awkward to use.

    The easiest way to "reset" our containers is to do it from within docker.
    The following commands will login to the docker containers and delete all of postgres's data:
    ```
    $ docker-compose run pg_normalized_batch bash -c 'rm -rf $PGDATA/*'
    $ docker-compose run pg_denormalized bash -c 'rm -rf $PGDATA/*'
    ```
    After running these commands, if you bring the containers down and back up, postgres will detect that the volumes are empty and re-run the `schema.sql` scripts to populate the databases.

    > **Warning:**
    > Do not delete the `$HOME/bigdata` folder (e.g. by runing `rm $HOME/bigdata`).
    > This "folder" is technically a symlink to a folder in the `/data` partition.
    > ```
    > $ ls -l $HOME/bigdata
    > lrwxrwxrwx 1 root root 35 Jan  3 15:04 /home/csci143example/bigdata -> /data/users_bigdata/csci143example/
    > ```
    > If you delete this symlink, you will not delete the folder and the underlying data.
    > Removing this symlink will cause lots of things to break for you.

    > **Hint:**
    > If you need help deleting the data for whatever reason,
    > let me (or the TA) know and we can delete it for you as a root user.

## Step 1: Load the Data

Copy the `load_tweets_batch.py` file and `load_denormalized.sh` files from the previous assignment into this folder.
Modify `load_tweets_parallel.sh` to use the port numbers specified in your `docker-compose.yml` file.

Then load the data into docker:
```
$ sh load_tweets_parallel.sh
================================================================================
load pg_denormalized
================================================================================
/data/tweets/geoTwitter21-01-02.zip
COPY 2979992
/data/tweets/geoTwitter21-01-04.zip
COPY 3044365
/data/tweets/geoTwitter21-01-05.zip
COPY 3038917
/data/tweets/geoTwitter21-01-03.zip
COPY 3143286
/data/tweets/geoTwitter21-01-01.zip
COPY 3189325
/data/tweets/geoTwitter21-01-10.zip
COPY 3129896
/data/tweets/geoTwitter21-01-09.zip
COPY 3157691
/data/tweets/geoTwitter21-01-08.zip
COPY 3148130
/data/tweets/geoTwitter21-01-07.zip
COPY 3306556
/data/tweets/geoTwitter21-01-06.zip
COPY 3376266
1587.10user 328.30system 18:18.76elapsed 174%CPU (0avgtext+0avgdata 17376maxresident)k
0inputs+27856outputs (0major+70545minor)pagefaults 0swaps
================================================================================
load pg_normalized_batch
================================================================================
2022-04-08 15:38:18.510811 /data/tweets/geoTwitter21-01-02.zip
...
...
...
23974.74user 1259.12system 51:55.11elapsed 810%CPU (0avgtext+0avgdata 3113188maxresident)k
5808inputs+86232outputs (3major+847834998minor)pagefaults 0swaps
```
Observe the runtimes in the above output to get a sense for how long your own queries should take.
Note that these operations max out the disk IO on the lambda server, and so if many students are running them at once, they could take considerably longer to complete.

### Note on Disk Usage

We're storing the twitter data in three formats (the original zip files, the denormalized database, and the normalized database).
Let's take a minute to see the total disk usage of each of these formats to help us understand the trade-offs of using each format.

The following commands will output the disk usage inside of the databases.
```
$ docker-compose exec pg_denormalized sh -c 'du -hd0 $PGDATA'
75G	/var/lib/postgresql/data
$ docker-compose exec pg_normalized_batch sh -c 'du -hd0 $PGDATA'
25G	/var/lib/postgresql/data
```
Notice that the denormalized database is using considerably more disk space than the normalized one.

To get the disk usage of the raw zip files, we first copy the definition of the `files` variable from the `load_tweets_parallel.sh` file into the terminal:
```
$ files='/data/tweets/geoTwitter21-01-01.zip
/data/tweets/geoTwitter21-01-02.zip
/data/tweets/geoTwitter21-01-03.zip
/data/tweets/geoTwitter21-01-04.zip
/data/tweets/geoTwitter21-01-05.zip
/data/tweets/geoTwitter21-01-06.zip
/data/tweets/geoTwitter21-01-07.zip
/data/tweets/geoTwitter21-01-08.zip
/data/tweets/geoTwitter21-01-09.zip
/data/tweets/geoTwitter21-01-10.zip'
```
Then run the following command:
```
$ du -ch $files
1.7G	/data/tweets/geoTwitter21-01-01.zip
1.6G	/data/tweets/geoTwitter21-01-02.zip
1.7G	/data/tweets/geoTwitter21-01-03.zip
1.6G	/data/tweets/geoTwitter21-01-04.zip
1.6G	/data/tweets/geoTwitter21-01-05.zip
1.8G	/data/tweets/geoTwitter21-01-06.zip
1.8G	/data/tweets/geoTwitter21-01-07.zip
1.7G	/data/tweets/geoTwitter21-01-08.zip
1.7G	/data/tweets/geoTwitter21-01-09.zip
1.7G	/data/tweets/geoTwitter21-01-10.zip
17G	total
```
We can see that the "flat" zip files use the least amount of data.

Why?

Postgres will keep all of the data compressed, but it has a lot of overhead in its heap tables (each row has overhead, and each page has overhead, and we will have empty space in each page).
We haven't discussed the `JSONB` column type in detail, but this also introduces significant overhead in order to have an efficient access operations.

## Step 2: Create indexes on the normalized database

I have provided a series of 5 sql queries for you, which you can find in the `sql.normalized_batch` folder.
You can time the running of these queries with the command
```
$ time docker-compose exec pg_normalized_batch ./run_tests.sh sql.normalized_batch
sql.normalized_batch/01.sql pass
sql.normalized_batch/02.sql pass
sql.normalized_batch/03.sql pass
sql.normalized_batch/04.sql pass
sql.normalized_batch/05.sql pass

real    2m5.882s
user    0m0.561s
sys     0m0.403s
```

Your first task is to create indexes so that the command above takes less than 5 seconds to run (i.e. one second per query).
Most of this runtime is overhead of the shell script.
If you open up psql and run the queries directly,
then you should see the queries taking only milliseconds to run.

> **NOTE:**
> None of your indexes should be partial indexes.
> This is so that you could theoretically replace any of the conditions with any other value,
> and the results will still be returned quickly.

> **HINT:**
> My solution creates 3 btree indexes and 1 gin index.
> Here's the output of running the command above with the indexes created:
> ```
> $ time docker-compose exec pg_normalized_batch   ./run_tests.sh sql.normalized_batch
> sql.normalized_batch/01.sql pass
> sql.normalized_batch/02.sql pass
> sql.normalized_batch/03.sql pass
> sql.normalized_batch/04.sql pass
> sql.normalized_batch/05.sql pass
> 
> real	0m3.176s
> user	0m0.571s
> sys	0m0.377s
> ```

> **IMPORTANT:**
> As you create your indexes, you should add them to the file `services/pg_normalized_batch/schema-indexes.sql`.
> (Like the `schema.sql` file, this file would get automatically run by postgres if you were to rebuild the containers+images.)
> In general, you never want to directly modify the schema of a production database.
> Instead, you write your schema-modifying code in a sql file,
> commit the sql file to your git repo,
> then execute the sql file.
> This ensures that you can always fully recreate your database schema from the project's git repo.

> **HINT:**
> Creating an index under default settings can take up to 30 minutes to complete.
> This is because by default, postgres uses only a single core and 20MB of memory.
> Your user accounts have permission to use up to all 80 cores, and up to 16GB of memory,
> and telling postgres to use these resouces will dramatically improve your index construction performance.
> You can find instructions for modifying these settings at: <https://www.cybertec-postgresql.com/en/postgresql-parallel-create-index-for-better-performance/>.

## Step 3: Create queries and indexes for the denormalized database

I have provided you the sql queries for the normalized database, but not for the denormalized one.
You will have to modify the files in `sql.denormalized` so that they produce the same output as the files in `sql.normalized_batch`.
The purpose of this exercise is twofold:

1. to give you practice writing queries into a denormalized database (you've only written queries for a normalized database at this point)
2. to give you practice writing queries and indexes at the same time (the exact queries you'll write in the real world will depend on the indexes you're able to create and vice versa)

You should add all of the indexes you create into the file `services/pg_denormalized/schema-indexes.sql`,
just like you did for the normalized database.

You can check the runtime and correctness of your denormalized queries with the command
```
$ time docker-compose exec pg_denormalized ./run_tests.sh sql.denormalized
```

> **HINT:**
> Here is the output of timing my SQL queries with no indexes present.
> ```
> $ time docker-compose exec pg_denormalized ./run_tests.sh sql.denormalized
> sql.denormalized/01.sql pass
> sql.denormalized/02.sql pass
> sql.denormalized/03.sql pass
> sql.denormalized/04.sql pass
> sql.denormalized/05.sql pass
> 
> real	39m6.800s
> user	0m0.875s
> sys	0m0.471s
> ```
> Notice that these runtimes are WAY slower than for the normalized database. 
> This is due to the overhead of the `JSONB` (more complicated processing needed to extract the information from the JSON, and more information needs to be read from the disk).
>
> After building the indexes, the runtimes are basically the same as for the normalized database:
> ```
> $ time docker-compose exec pg_denormalized ./run_tests.sh sql.denormalized
> sql.denormalized/01.sql pass
> sql.denormalized/02.sql pass
> sql.denormalized/03.sql pass
> sql.denormalized/04.sql pass
> sql.denormalized/05.sql pass
> 
> real	0m2.903s
> user	0m0.621s
> sys	0m0.389s
> ```
>
> Notice that with indexes, the results of the denormalized database are just as fast as with the normalized database.

## Submission

We will not use github actions in this assignment,
since this assignment uses too much disk space and computation.
In general, there are no great techniques for benchmarking/testing programs on large datasets.
The best solution is to test on small datasets (like we did for the first versions of twitter\_postgres),
and carefully design those tests so that they ensure good performance on the large datasets.
But runtime issues involving bad indexes are notorious for causing production related issues that can not be reproduced/debugged in a development environment.

To submit your assignment:

1. Run the following commands
   ```
   $ ( time docker-compose exec pg_normalized_batch ./run_tests.sh sql.normalized_batch ) > results.normalized_batch 2>&1
   $ ( time docker-compose exec pg_denormalized     ./run_tests.sh sql.denormalized     ) > results.denormalized     2>&1
   ```
   This will create two files in your repo that contain the runtimes and results of your test cases.
   In the command above:
   1. `( ... )` is called a subshell in bash.
      The `time` command is an internal built-in command in bash and not a separate executable file,
      and it is necessary to wrap it in a subshell in order to redirect its output.
   1. `2>&1` redirects stderr (2) to stdout (1), and since stdout is being redirected to a file, stderr will also be redirected to that file.
      The output of the `time` command goes to stderr, and so this combined with the subshell ensure that the time command's output gets sent into the results files.

       > **ASIDE:**
       > Mastering these shell redirection tricks is a HUGE timesaver,
       > and something that I'd recommend anyone working on remote servers professionally do.

1. Add the `results.*`, `sql.denormalized/*`, and `services/*/schema-indexes.sql` files to your git repo, commit, and push to github.

1. Submit a link to your forked repo to sakai.

### Grading

The assignment is worth 32 points.

1. The normalized sql queries are worth 16 points.

    You must pass all the test cases to get any credit.
    (They should already be passing, so this will be easy.)

    If your queries take at least a second longer than 4 seconds,
    you will lose 2 points per second.

1. The denormalized sql queries are worth 16 points.

    You must pass all the test cases to get any credit.

    If your queries take at least a second longer than 4 seconds,
    you will lose 2 points per second.

The grader will check the `results.*` files in your github repos to grade your timing.
If these files are not created correctly, you will receive a 0.
