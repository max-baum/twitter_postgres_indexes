WITH filtered_tweets AS (
  SELECT
    data->>'id' AS id,
    data
  FROM tweets_jsonb
  WHERE data->>'lang' = 'en'
    AND to_tsvector(
          'english',
          COALESCE(
            data->'extended_tweet'->>'full_text',
            data->>'text'
          )
        ) @@ to_tsquery('english', 'coronavirus')
),
all_hashtags AS (
  SELECT DISTINCT
    ft.id,
    h1.value->>'text' AS tag
  FROM filtered_tweets ft
  CROSS JOIN LATERAL jsonb_array_elements(ft.data->'entities'->'hashtags') AS h1

  UNION

  SELECT DISTINCT
    ft.id,
    h2.value->>'text' AS tag
  FROM filtered_tweets ft
  CROSS JOIN LATERAL jsonb_array_elements(ft.data->'extended_tweet'->'entities'->'hashtags') AS h2
)
SELECT
  '#' || tag AS tag,
  COUNT(*) AS count
FROM all_hashtags
GROUP BY tag
ORDER BY count DESC, tag
LIMIT 1000;

