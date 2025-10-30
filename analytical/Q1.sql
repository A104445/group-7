SELECT repository_id, ticket_id, created_by, type, title, time_to_close
FROM (
    SELECT t.repository_id, t.ticket_id, t.created_by, t.type, t.title, t.time_to_close,
        rank() OVER(PARTITION BY type ORDER BY time_to_close desc) AS rank
    FROM (
        SELECT repository_id, ticket_id, created_by, type,
            closed_at - opened_at AS time_to_close, title
        FROM ticket
        WHERE (status = 'merged' OR status = 'closed')
            AND length(data) > 300
            AND (title || data) LIKE '%perf%'
    ) t
    JOIN repository r ON r.id = t.repository_id
    JOIN users u ON u.username = t.created_by
    WHERE r.owner <> u.username
        AND NOT r.is_archived
)
WHERE rank <= 100
ORDER BY 4, 6 DESC;
