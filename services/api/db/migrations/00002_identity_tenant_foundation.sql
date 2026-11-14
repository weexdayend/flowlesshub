-- +goose Up
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

CREATE SCHEMA identity;
CREATE SCHEMA tenant;

CREATE TABLE identity.users (
    id UUID PRIMARY KEY,
    email_normalized TEXT NOT NULL,
    display_name TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT users_email_normalized_check
        CHECK (email_normalized = lower(btrim(email_normalized)) AND email_normalized <> ''),
    CONSTRAINT users_display_name_check
        CHECK (display_name = btrim(display_name) AND length(display_name) BETWEEN 1 AND 120),
    CONSTRAINT users_password_hash_check
        CHECK (password_hash LIKE 'fh1$argon2id$v=19$%'),
    CONSTRAINT users_status_check
        CHECK (status IN ('active', 'disabled'))
);
CREATE UNIQUE INDEX users_email_normalized_uq ON identity.users (email_normalized);

CREATE TABLE tenant.organizations (
    id UUID PRIMARY KEY,
    slug_normalized TEXT NOT NULL,
    display_name TEXT NOT NULL,
    legal_name TEXT,
    status TEXT NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT organizations_slug_normalized_check
        CHECK (slug_normalized = lower(btrim(slug_normalized)) AND slug_normalized ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
    CONSTRAINT organizations_display_name_check
        CHECK (display_name = btrim(display_name) AND length(display_name) BETWEEN 2 AND 120),
    CONSTRAINT organizations_legal_name_check
        CHECK (legal_name IS NULL OR (legal_name = btrim(legal_name) AND length(legal_name) BETWEEN 1 AND 180)),
    CONSTRAINT organizations_status_check
        CHECK (status IN ('active', 'suspended'))
);
CREATE UNIQUE INDEX organizations_slug_normalized_uq ON tenant.organizations (slug_normalized);

CREATE TABLE tenant.memberships (
    id UUID PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES tenant.organizations (id) ON DELETE RESTRICT,
    user_id UUID NOT NULL REFERENCES identity.users (id) ON DELETE RESTRICT,
    role TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT memberships_organization_user_uq UNIQUE (organization_id, user_id),
    CONSTRAINT memberships_role_check CHECK (role IN ('owner', 'admin', 'member')),
    CONSTRAINT memberships_status_check CHECK (status IN ('active', 'invited', 'suspended'))
);
CREATE INDEX memberships_user_active_idx
    ON tenant.memberships (user_id, organization_id)
    WHERE status = 'active';
CREATE INDEX memberships_organization_active_idx
    ON tenant.memberships (organization_id, user_id)
    WHERE status = 'active';
CREATE TABLE identity.sessions (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES identity.users (id) ON DELETE CASCADE,
    token_digest BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    last_used_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at TIMESTAMPTZ,
    CONSTRAINT sessions_token_digest_length_check CHECK (octet_length(token_digest) = 32),
    CONSTRAINT sessions_expiry_check CHECK (expires_at > created_at)
);
CREATE UNIQUE INDEX sessions_token_digest_uq ON identity.sessions (token_digest);
CREATE INDEX sessions_active_user_expiry_idx
    ON identity.sessions (user_id, expires_at)
    WHERE revoked_at IS NULL;

CREATE TABLE identity.auth_events (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES identity.users (id) ON DELETE SET NULL,
    organization_id UUID REFERENCES tenant.organizations (id) ON DELETE SET NULL,
    event_type TEXT NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT auth_events_type_check
        CHECK (event_type IN ('login_succeeded', 'login_failed', 'logout', 'owner_bootstrapped'))
);
CREATE INDEX auth_events_occurred_at_idx ON identity.auth_events (occurred_at DESC);
CREATE INDEX auth_events_user_occurred_at_idx ON identity.auth_events (user_id, occurred_at DESC);

-- +goose Down
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
-- squawk-ignore ban-drop-table -- intentional teardown of the S1.1 foundation during rollback
DROP TABLE identity.auth_events;
-- squawk-ignore ban-drop-table -- intentional teardown of the S1.1 foundation during rollback
DROP TABLE identity.sessions;
-- squawk-ignore ban-drop-table -- intentional teardown of the S1.1 foundation during rollback
DROP TABLE tenant.memberships;
-- squawk-ignore ban-drop-table -- intentional teardown of the S1.1 foundation during rollback
DROP TABLE tenant.organizations;
-- squawk-ignore ban-drop-table -- intentional teardown of the S1.1 foundation during rollback
DROP TABLE identity.users;
-- squawk-ignore ban-drop-schema -- intentional teardown of the S1.1 tenant schema during rollback
DROP SCHEMA tenant;
-- squawk-ignore ban-drop-schema -- intentional teardown of the S1.1 identity schema during rollback
DROP SCHEMA identity;
