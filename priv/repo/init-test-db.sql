-- Create the test database for ExUnit tests.
-- This script runs once when the PostgreSQL container is first initialized
-- (via docker-entrypoint-initdb.d). It does NOT run on subsequent starts
-- because PostgreSQL skips initdb when the data volume already exists.
--
-- If you need to recreate the test database on an existing volume:
--   docker compose exec postgres psql -U sle -c "CREATE DATABASE sle_test OWNER sle;"

CREATE DATABASE sle_test OWNER sle;
