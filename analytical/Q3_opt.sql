SELECT interval, event, SUM(count) AS count
FROM (
    SELECT 
        date_bin('15 minutes', created_at, '2009-01-01') AS interval,
        'commit' AS event,
        COUNT(*) AS count
    FROM commit
    WHERE created_at BETWEEN '2022-01-01' AND '2025-01-01'
    GROUP BY 1

    UNION ALL

    SELECT 
        date_bin('15 minutes', opened_at, '2009-01-01') AS interval,
        'ticket_opened' AS event,
        COUNT(*) AS count
    FROM ticket
    WHERE opened_at BETWEEN '2022-01-01' AND '2025-01-01'
    GROUP BY 1

    UNION ALL

    SELECT 
        date_bin('15 minutes', closed_at, '2009-01-01') AS interval,
        'ticket_closed' AS event,
        COUNT(*) AS count
    FROM ticket
    WHERE closed_at BETWEEN '2022-01-01' AND '2025-01-01'
      AND closed_at IS NOT NULL
    GROUP BY 1

    UNION ALL

    SELECT 
        date_bin('15 minutes', created_at, '2009-01-01') AS interval,
        'repository' AS event,
        COUNT(*) AS count
    FROM repository
    WHERE created_at BETWEEN '2022-01-01' AND '2025-01-01'
    GROUP BY 1

    UNION ALL

    SELECT 
        date_bin('15 minutes', created_at, '2009-01-01') AS interval,
        'user' AS event,
        COUNT(*) AS count
    FROM users
    WHERE created_at BETWEEN '2022-01-01' AND '2025-01-01'
    GROUP BY 1

    UNION ALL

    SELECT 
        date_bin('15 minutes', starred_at, '2009-01-01') AS interval,
        'star' AS event,
        COUNT(*) AS count
    FROM star
    WHERE starred_at BETWEEN '2022-01-01' AND '2025-01-01'
    GROUP BY 1
)
GROUP BY interval, event
ORDER BY interval, event;