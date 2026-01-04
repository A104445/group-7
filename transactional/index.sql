CREATE INDEX IF NOT EXISTS idx_repository_description_gin ON repository USING GIN(to_tsvector('english', description));
CREATE INDEX IF NOT EXISTS idx_repository_owner_pushed_at ON repository (owner, pushed_at DESC);
CREATE INDEX IF NOT EXISTS idx_repository_languages_language_id ON repository_languages (language_id);