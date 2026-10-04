-- PostgreSQL 17+ | Sprint 1 | 002-create-identity

CREATE TABLE identity.users (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cognito_sub varchar(128) NOT NULL,
    email varchar(320) NOT NULL,
    normalized_email varchar(320) GENERATED ALWAYS AS (lower(btrim(email))) STORED,
    CONSTRAINT pk_users PRIMARY KEY (id),
    CONSTRAINT uq_users_cognito_sub UNIQUE (cognito_sub),
    CONSTRAINT uq_users_normalized_email UNIQUE (normalized_email),
    CONSTRAINT ck_users_sub CHECK (btrim(cognito_sub) <> ''),
    CONSTRAINT ck_users_email CHECK (btrim(email) <> '' AND position('@' in email) > 1)
);

COMMENT ON TABLE identity.users IS 'Perfil interno; credenciais e tokens permanecem no Cognito.';

CREATE TABLE identity.login_attempts (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    email_hash bytea NOT NULL,
    ip_hash bytea NOT NULL,
    correlation_id uuid,
    CONSTRAINT pk_login_attempts PRIMARY KEY (id),
    CONSTRAINT ck_login_attempts_hashes CHECK (octet_length(email_hash) = 32 AND octet_length(ip_hash) = 32)
);

COMMENT ON TABLE identity.login_attempts IS 'Falhas de login para janela móvel; identificadores HMAC de 32 bytes.';

CREATE INDEX ix_login_attempts_email_window ON identity.login_attempts (email_hash, created_at);

CREATE INDEX ix_login_attempts_ip_window ON identity.login_attempts (ip_hash, created_at);

CREATE INDEX ix_login_attempts_retention ON identity.login_attempts (created_at);

CREATE TABLE identity.login_blocks (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    key_kind varchar(16) NOT NULL,
    key_hash bytea NOT NULL,
    blocked_until timestamptz NOT NULL,
    CONSTRAINT pk_login_blocks PRIMARY KEY (id),
    CONSTRAINT uq_login_blocks_key_kind_key_hash UNIQUE (key_kind, key_hash),
    CONSTRAINT ck_login_blocks_kind CHECK (key_kind IN ('email', 'ip', 'email_ip')),
    CONSTRAINT ck_login_blocks_hash CHECK (octet_length(key_hash) = 32),
    CONSTRAINT ck_login_blocks_deadline CHECK (blocked_until > created_at)
);

COMMENT ON TABLE identity.login_blocks IS 'Bloqueios compartilhados entre réplicas; validade consultada em cada login.';

CREATE INDEX ix_login_blocks_expiration ON identity.login_blocks (blocked_until);

CREATE TABLE identity.identity_reconciliations (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    operation_key varchar(200) NOT NULL,
    cognito_sub varchar(128),
    reason_code varchar(100) NOT NULL,
    status varchar(16) NOT NULL DEFAULT 'pending',
    resolved_at timestamptz,
    correlation_id uuid,
    CONSTRAINT pk_identity_reconciliations PRIMARY KEY (id),
    CONSTRAINT uq_identity_reconciliations_operation_key UNIQUE (operation_key),
    CONSTRAINT ck_identity_reconciliations_status CHECK (status IN ('pending', 'resolved')),
    CONSTRAINT ck_identity_reconciliations_resolution CHECK ((status = 'pending' AND resolved_at IS NULL) OR (status = 'resolved' AND resolved_at IS NOT NULL AND resolved_at >= created_at))
);

COMMENT ON TABLE identity.identity_reconciliations IS 'Acompanhamento operacional síncrono de divergências Cognito/perfil.';

CREATE INDEX ix_identity_reconciliations_pending ON identity.identity_reconciliations (created_at) WHERE status = 'pending';

CREATE TABLE identity.idempotency_records (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    scope_key varchar(160) NOT NULL,
    actor_user_id uuid,
    operation varchar(100) NOT NULL,
    idempotency_key varchar(200) NOT NULL,
    request_hash bytea NOT NULL,
    status varchar(16) NOT NULL DEFAULT 'in_progress',
    response_status smallint,
    response_payload jsonb,
    completed_at timestamptz,
    expires_at timestamptz NOT NULL,
    CONSTRAINT pk_idempotency_records PRIMARY KEY (id),
    CONSTRAINT uq_idempotency_records_scope_key_operation_idempotency_key UNIQUE (scope_key, operation, idempotency_key),
    CONSTRAINT ck_idempotency_records_scope CHECK (btrim(scope_key) <> ''),
    CONSTRAINT ck_idempotency_records_key CHECK (btrim(operation) <> '' AND btrim(idempotency_key) <> ''),
    CONSTRAINT ck_idempotency_records_hash CHECK (octet_length(request_hash) = 32),
    CONSTRAINT ck_idempotency_records_status CHECK (status IN ('in_progress','succeeded','failed')),
    CONSTRAINT ck_idempotency_records_expiry CHECK (expires_at > created_at),
    CONSTRAINT ck_idempotency_records_result CHECK ((status = 'in_progress' AND completed_at IS NULL AND response_status IS NULL AND response_payload IS NULL) OR (status IN ('succeeded','failed') AND completed_at IS NOT NULL AND completed_at >= created_at AND response_status IS NOT NULL AND response_status BETWEEN 100 AND 599)),
    CONSTRAINT fk_idempotency_records_actor FOREIGN KEY (actor_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT
);

COMMENT ON TABLE identity.idempotency_records IS 'Controle de retries síncronos; fingerprint e resposta nunca devem conter credenciais.';

CREATE INDEX ix_idempotency_records_expiration ON identity.idempotency_records (expires_at);

CREATE INDEX ix_idempotency_records_fk_actor ON identity.idempotency_records (actor_user_id);

CREATE TABLE identity.audit_logs (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actor_user_id uuid,
    action varchar(100) NOT NULL,
    entity_type varchar(64) NOT NULL,
    entity_id uuid,
    correlation_id uuid,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT pk_audit_logs PRIMARY KEY (id),
    CONSTRAINT ck_audit_logs_metadata CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT ck_audit_logs_labels CHECK (btrim(action) <> '' AND btrim(entity_type) <> ''),
    CONSTRAINT fk_audit_logs_actor FOREIGN KEY (actor_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT
);

COMMENT ON TABLE identity.audit_logs IS 'Trilha de metadados; valores financeiros ficam nas revisões protegidas, nunca em logs operacionais.';

CREATE INDEX ix_audit_logs_history ON identity.audit_logs (created_at);

CREATE INDEX ix_audit_logs_entity ON identity.audit_logs (entity_type, entity_id, created_at);

CREATE INDEX ix_audit_logs_fk_actor ON identity.audit_logs (actor_user_id);
