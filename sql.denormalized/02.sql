WITH relevant_tweets AS (
  SELECT DISTINCT data->>'id' AS id, data
  FROM tweets_jsonb
  WHERE
    data->'entities'->'hashtags' @@ '$[*].text == "coronavirus"'
    OR data->'extended_tweet'->'entities'->'hashtags' @@ '$[*].text == "coronavirus"'
),
all_hashtags AS (
  SELECT id, h.value->>'text' AS tag 
  FROM relevant_tweets
  LEFT JOIN LATERAL jsonb_array_elements(data->'entities'->'hashtags') AS h ON TRUE
  UNION
  SELECT id, h.value->>'text' AS tag 
  FROM relevant_tweets
  LEFT JOIN LATERAL jsonb_array_elements(data->'extended_tweet'->'entities'->'hashtags') AS h ON TRUE
)
SELECT '#' || tag AS tag, COUNT(*) AS count
FROM all_hashtags
Where tag <> ''
GROUP BY tag 
ORDER BY count DESC, tag 
LIMIT 1000;
