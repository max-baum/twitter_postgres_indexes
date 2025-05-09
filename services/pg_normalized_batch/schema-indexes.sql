SET max_parallel_maintenance_workers TO 80;
SET maintenance_work_mem TO '16 GB';

CREATE INDEX idx1 ON tweet_tags(tag);

CREATE INDEX idx2 ON tweet_tags(id_tweets);

CREATE INDEX idx3 ON tweets(lang);

CREATE INDEX idx4 ON tweets(id_tweets);

CREATE INDEX idx5 ON tweets USING GIN (to_tsvector('english', text)) WHERE lang = 'en';
