-- Q1
CREATE TYPE ticket_type_enum AS ENUM ('issue', 'pull_request');

ALTER TABLE ticket ALTER COLUMN type TYPE ticket_type_enum USING type::ticket_type_enum;

CREATE INDEX IF NOT EXISTS idx_ticket_analytic_rank 
ON ticket (type, duration DESC) 
WHERE status IN ('merged', 'closed');

-- Q2
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_star_optimize 
ON star (starred_at, repository_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_repo_lang_optimize 
ON repository_languages (repository_id, size DESC);

-- Q3
CREATE INDEX IF NOT EXISTS idx_commit_created_at ON commit (created_at);
CREATE INDEX IF NOT EXISTS idx_repository_created_at ON repository (created_at);
CREATE INDEX IF NOT EXISTS idx_star_starred_at ON star (starred_at);
CREATE INDEX IF NOT EXISTS idx_ticket_closed_at ON ticket (closed_at);
CREATE INDEX IF NOT EXISTS idx_ticket_opened_at ON ticket (opened_at);
CREATE INDEX IF NOT EXISTS idx_users_created_at ON users (created_at);

-- Q4
CREATE INDEX IF NOT EXISTS idx_star_username ON star (username);