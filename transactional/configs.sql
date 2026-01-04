ALTER SYSTEM SET shared_buffers = '4GB';

ALTER SYSTEM SET work_mem = '16MB';

ALTER SYSTEM SET max_parallel_workers_per_gather = 4;

ALTER SYSTEM SET max_parallel_workers = 8;