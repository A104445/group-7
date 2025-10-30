-- update the sequences
SELECT setval('repository_id_seq', (SELECT MAX(id) FROM Repository));
SELECT setval('language_id_seq', (SELECT MAX(id) FROM Language));
SELECT setval('license_id_seq', (SELECT MAX(id) FROM License));
SELECT setval('topic_id_seq', (SELECT MAX(id) FROM Topic));
