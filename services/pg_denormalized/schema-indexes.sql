SET max_parallel_maintenance_workers TO 80;
SET maintenance_work_mem TO '1 GB';

--CREATE INDEX idx_hashtags ON public.tweets_jsonb USING gin ((((data -> 'entities'::text) -> 'hashtags'::text)) jsonb_path_ops);

--CREATE INDEX idx_extended_tweet_hashtags ON tweets_jsonb USING gin ((data->'extended_tweet'->'entities'->'hashtags') jsonb_path_ops);

CREATE INDEX idx_tweets_jsonb_id ON tweets_jsonb ((data->>'id'));

CREATE INDEX idx_tweets_jsonb_lang ON tweets_jsonb ((data->>'lang'));

CREATE INDEX idx_tweets_jsonb_text_tsv ON tweets_jsonb
USING GIN (
  to_tsvector('english', COALESCE(data->'extended_tweet'->>'full_text', data->>'text'))
);
