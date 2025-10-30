SELECT date_bin('15 minutes', date, '2009-01-01') AS interval, event, count(*) AS count
FROM (
    SELECT 'commit' AS event, created_at AS date
    FROM commit
    UNION ALL
    SELECT 'ticket_opened', opened_at
    FROM ticket
    UNION ALL
    SELECT 'ticket_closed', closed_at
    FROM ticket
    WHERE closed_at IS NOT NULL
    UNION ALL
    SELECT 'repository', created_at
    FROM repository
    UNION ALL
    SELECT 'user', created_at
    FROM users
    UNION ALL
    SELECT 'star', starred_at
    FROM star
)
WHERE date BETWEEN '2022-01-01' AND '2025-01-01'
GROUP BY 1, 2
ORDER BY 1, 2;

-- for duckdb, replace:
--  date_bin('15 minutes', date, '2009-01-01')
-- with:
--  time_bucket(interval '15 minutes', date, '2009-01-01'::timestamp)
