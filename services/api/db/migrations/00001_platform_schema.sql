-- +goose Up
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
CREATE SCHEMA IF NOT EXISTS platform;

-- +goose Down
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
-- squawk-ignore ban-drop-schema -- intentional Down migration for the empty foundation schema
DROP SCHEMA IF EXISTS platform CASCADE;
