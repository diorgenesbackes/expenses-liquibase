SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

-- Preserve old attempts while allowing email-only protection for new logins.
ALTER TABLE identity.login_attempts ALTER COLUMN ip_hash DROP NOT NULL;

CREATE TABLE identity.login_guards (
    email_hash bytea PRIMARY KEY CHECK (octet_length(email_hash) = 32),
    owner uuid,
    lease_until timestamptz,
    CHECK ((owner IS NULL) = (lease_until IS NULL))
);
COMMENT ON TABLE identity.login_guards IS 'Short login leases shared between replicas; no transaction spans Cognito I/O.';

CREATE TABLE identity.sessions (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES identity.users(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    access_expires_at timestamptz NOT NULL,
    access_hash bytea NOT NULL CHECK (octet_length(access_hash) = 32),
    refresh_hash bytea NOT NULL CHECK (octet_length(refresh_hash) = 32),
    state varchar(16) NOT NULL CHECK (state IN ('active', 'refreshing', 'revoked')),
    refresh_owner uuid,
    revoked_at timestamptz,
    CHECK (expires_at > created_at),
    CHECK (updated_at >= created_at),
    CHECK ((state = 'refreshing') = (refresh_owner IS NOT NULL)),
    CHECK ((state = 'revoked') = (revoked_at IS NOT NULL))
);
CREATE INDEX ix_sessions_user ON identity.sessions(user_id);
CREATE INDEX ix_sessions_expiration ON identity.sessions(expires_at);
COMMENT ON TABLE identity.sessions IS 'Immediate local revocation. Only token hashes; refresh credentials stay in protected HttpOnly cookies.';
