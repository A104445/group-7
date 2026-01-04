SELECT r.id, r.owner || '/' || r.name, r.description
  FROM users u
  JOIN star s1 ON u.username = s1.username
  JOIN star s2 ON s1.repository_id = s2.repository_id
      AND s1.username <> s2.username
  JOIN star s3 ON s3.username = s2.username
  JOIN repository r ON r.id = s3.repository_id
  WHERE u.username = 'christopherharmon25'
  AND NOT EXISTS (
      SELECT 1
      FROM star s_exclude
      WHERE s_exclude.repository_id = s3.repository_id
      AND s_exclude.username = 'christopherharmon25'
  )
  GROUP BY 1, 2, 3
  ORDER BY count(*) DESC
  LIMIT 25;
