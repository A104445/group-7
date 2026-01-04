WITH top_stars_filtered AS (
    SELECT 
        repository_id,
        count(*) AS count
    FROM star s
    WHERE s.starred_at >= '2024-12-01'::date 
      AND s.starred_at < ('2024-12-01'::date + INTERVAL '1 month')
    GROUP BY repository_id
    ORDER BY count DESC
    LIMIT 25
)
SELECT 
    t.repository_id AS id,
    r.owner || '/' || r.name AS full_name,
    '2024-12-01 00:00:00+00'::timestamptz AS month,
    (
        SELECT (array_agg(l.name ORDER BY rl.size DESC))[:3]
        FROM repository_languages rl
        JOIN language l ON l.id = rl.language_id
        WHERE rl.repository_id = t.repository_id
    ) AS languages,
    t.count
FROM top_stars_filtered t
JOIN repository r ON r.id = t.repository_id
ORDER BY t.count DESC;