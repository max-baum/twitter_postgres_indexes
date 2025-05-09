SELECT                                      
    q.lang,
    count(*) as count
FROM (                                                                    
    SELECT DISTINCT data->>'id' as id, data->>'lang' as lang
    FROM tweets_jsonb
    WHERE data->'entities'->'hashtags'@@'$[*].text == "coronavirus"'
    UNION
    SELECT DISTINCT data->>'id' as id, data->>'lang' as lang
    FROM tweets_jsonb
    WHERE data->'extended_tweet'->'entities'->'hashtags'@@'$[*].text == "coronavirus"'
) q
GROUP BY q.lang
ORDER BY count DESC, q.lang;
