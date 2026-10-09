SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

CREATE TABLE identity.registration_operations (
    id uuid NOT NULL,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    normalized_email varchar(320) NOT NULL,
    idempotency_record_id uuid NOT NULL,
    correlation_id uuid NOT NULL,
    stage varchar(32) NOT NULL,
    cognito_username varchar(128),
    cognito_sub varchar(128),
    user_id uuid,
    version bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_registration_operations PRIMARY KEY (id),
    CONSTRAINT uq_registration_idempotency UNIQUE (idempotency_record_id),
    CONSTRAINT fk_registration_idempotency FOREIGN KEY (idempotency_record_id)
        REFERENCES identity.idempotency_records(id) ON DELETE RESTRICT,
    CONSTRAINT fk_registration_user FOREIGN KEY (user_id)
        REFERENCES identity.users(id) ON DELETE RESTRICT,
    CONSTRAINT ck_registration_email CHECK (normalized_email <> '' AND normalized_email = lower(btrim(normalized_email))),
    CONSTRAINT ck_registration_stage CHECK (stage IN ('reserved','principal_created','password_ready','completed','failed','reconciliation_required')),
    CONSTRAINT ck_registration_version CHECK (version >= 0),
    CONSTRAINT ck_registration_timestamps CHECK (updated_at >= created_at),
    CONSTRAINT ck_registration_principal CHECK ((cognito_username IS NULL AND cognito_sub IS NULL)
        OR (cognito_username IS NOT NULL AND cognito_sub IS NOT NULL AND btrim(cognito_username) <> '' AND btrim(cognito_sub) <> '')),
    CONSTRAINT ck_registration_known CHECK (stage NOT IN ('principal_created','password_ready','completed') OR cognito_sub IS NOT NULL),
    CONSTRAINT ck_registration_completion CHECK ((stage = 'completed') = (user_id IS NOT NULL))
);

-- One active owner per normalized email, including unresolved operations after a crash.
CREATE UNIQUE INDEX uq_registration_active_email ON identity.registration_operations(normalized_email)
    WHERE stage IN ('reserved','principal_created','password_ready','reconciliation_required');
CREATE INDEX ix_registration_user ON identity.registration_operations(user_id);
CREATE INDEX ix_registration_recovery ON identity.registration_operations(updated_at)
    WHERE stage IN ('reserved','principal_created','password_ready','reconciliation_required');
COMMENT ON TABLE identity.registration_operations IS
    'Synchronous registration journal. No credentials. Uncertain outcomes require operational reconciliation; expiry never authorizes a retry.';
