SELECT COUNT(DISTINCT data->>'id') AS count
FROM tweets_jsonb
WHERE 
    data->'entities'->'hashtags' @> '[{"text": "coronavirus"}]'::jsonb
    OR data->'extended_tweet'->'entities'->'hashtags' @> '[{"text": "coronavirus"}]'::jsonb;

