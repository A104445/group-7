SELECT id, full_name, languages, count
FROM (
    SELECT *, rank() OVER(PARTITION BY month ORDER BY count DESC) AS rank
    FROM (
        SELECT r.id AS id,
            r.owner || '/' || r.name AS full_name,
            date_trunc('month', s.starred_at) AS month,
            l.languages,
            count(s.repository_id) AS count
        FROM repository r
        LEFT JOIN star s ON s.repository_id = r.id
        LEFT JOIN (
            SELECT rl.repository_id, (array_agg(l.name ORDER BY rl.size DESC))[:3] AS languages
            FROM repository_languages rl
            JOIN language l ON l.id = rl.language_id
            GROUP BY 1
        ) l ON l.repository_id = r.id
        GROUP BY 1, 2, 3, 4
    )
)
WHERE rank <= 25
    AND month = '2024-12-01'
ORDER BY count DESC;
