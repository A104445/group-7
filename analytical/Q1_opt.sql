SELECT 
       top_tickets.repository_id,
       top_tickets.ticket_id,
       top_tickets.created_by,
       top_tickets.type,
       top_tickets.title,
       top_tickets.time_to_close
   FROM (
       VALUES 
           ('issue'::ticket_type_enum), 
           ('pull_request'::ticket_type_enum)
   ) AS types(type)
   CROSS JOIN LATERAL (
       SELECT 
           t.repository_id, t.ticket_id, t.created_by, t.type, t.title, 
           t.duration as time_to_close
       FROM ticket t
       JOIN repository r ON r.id = t.repository_id
       JOIN users u ON u.username = t.created_by
       WHERE 
           t.type = types.type
           AND t.status IN ('merged', 'closed')
           AND length(t.data) > 300
           AND (t.title || t.data) LIKE '%perf%'
           AND r.owner <> u.username
           AND NOT r.is_archived
       ORDER BY t.duration DESC
       LIMIT 100
   ) top_tickets
   ORDER BY 4,6 DESC;