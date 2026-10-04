-- PostgreSQL 17+ | Sprint 1 | 003-create-household

CREATE TABLE household.households (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    name varchar(160) NOT NULL,
    normalized_name varchar(160) GENERATED ALWAYS AS (lower(btrim(name))) STORED,
    currency_code varchar(3) NOT NULL DEFAULT 'BRL',
    time_zone varchar(64) NOT NULL DEFAULT 'America/Sao_Paulo',
    membership_version bigint NOT NULL DEFAULT 1,
    created_by_user_id uuid NOT NULL,
    deleted_at timestamptz,
    deleted_by_user_id uuid,
    recoverable_until timestamptz,
    CONSTRAINT pk_households PRIMARY KEY (id),
    CONSTRAINT ck_households_name CHECK (btrim(name) <> ''),
    CONSTRAINT ck_households_currency CHECK (currency_code = 'BRL'),
    CONSTRAINT ck_households_zone CHECK (btrim(time_zone) <> ''),
    CONSTRAINT ck_households_version CHECK (membership_version > 0),
    CONSTRAINT ck_households_deletion CHECK ((deleted_at IS NULL AND deleted_by_user_id IS NULL AND recoverable_until IS NULL) OR (deleted_at IS NOT NULL AND deleted_by_user_id IS NOT NULL AND recoverable_until IS NOT NULL AND recoverable_until >= deleted_at)),
    CONSTRAINT fk_households_created_by FOREIGN KEY (created_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_households_deleted_by FOREIGN KEY (deleted_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT
);

COMMENT ON TABLE household.households IS 'Casa; exclusão lógica bloqueia acesso comum por 30 dias antes da eliminação.';

CREATE INDEX ix_households_purge ON household.households (recoverable_until) WHERE deleted_at IS NOT NULL;

CREATE INDEX ix_households_fk_created_by ON household.households (created_by_user_id);

CREATE INDEX ix_households_fk_deleted_by ON household.households (deleted_by_user_id);

CREATE TABLE household.household_members (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    user_id uuid NOT NULL,
    role varchar(24) NOT NULL,
    financial_position smallint,
    joined_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    left_at timestamptz,
    created_by_user_id uuid,
    CONSTRAINT pk_household_members PRIMARY KEY (id),
    CONSTRAINT uq_household_members_household_id_id UNIQUE (household_id, id),
    CONSTRAINT ck_household_members_role CHECK (role IN ('household_admin', 'financial_member', 'viewer')),
    CONSTRAINT ck_household_members_position CHECK (financial_position IN (1, 2)),
    CONSTRAINT ck_household_members_role_position CHECK ((role <> 'viewer' OR financial_position IS NULL) AND (role <> 'financial_member' OR financial_position IS NOT NULL)),
    CONSTRAINT ck_household_members_dates CHECK (left_at IS NULL OR left_at >= joined_at),
    CONSTRAINT fk_household_members_household FOREIGN KEY (household_id)
        REFERENCES household.households (id) ON DELETE RESTRICT,
    CONSTRAINT fk_household_members_user FOREIGN KEY (user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_household_members_created_by FOREIGN KEY (created_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT
);

COMMENT ON TABLE household.household_members IS 'Vínculo histórico; posições financeiras 1/2 limitam os responsáveis ativos.';

CREATE UNIQUE INDEX ix_household_members_active_user ON household.household_members (household_id, user_id) WHERE left_at IS NULL;

CREATE UNIQUE INDEX ix_household_members_active_position ON household.household_members (household_id, financial_position) WHERE left_at IS NULL AND financial_position IS NOT NULL;

CREATE INDEX ix_household_members_fk_user ON household.household_members (user_id);

CREATE INDEX ix_household_members_fk_created_by ON household.household_members (created_by_user_id);

CREATE TABLE household.household_invitations (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    email varchar(320) NOT NULL,
    normalized_email varchar(320) GENERATED ALWAYS AS (lower(btrim(email))) STORED,
    role varchar(24) NOT NULL DEFAULT 'financial_member',
    financial_position smallint,
    token_hash bytea NOT NULL,
    status varchar(16) NOT NULL DEFAULT 'pending',
    expires_at timestamptz NOT NULL,
    accepted_at timestamptz,
    cancelled_at timestamptz,
    created_by_user_id uuid NOT NULL,
    accepted_by_user_id uuid,
    cancelled_by_user_id uuid,
    CONSTRAINT pk_household_invitations PRIMARY KEY (id),
    CONSTRAINT uq_household_invitations_token_hash UNIQUE (token_hash),
    CONSTRAINT ck_household_invitations_hash CHECK (octet_length(token_hash) = 32),
    CONSTRAINT ck_household_invitations_email CHECK (position('@' in email) > 1),
    CONSTRAINT ck_household_invitations_role CHECK (role IN ('household_admin', 'financial_member', 'viewer')),
    CONSTRAINT ck_household_invitations_position CHECK (financial_position IN (1, 2)),
    CONSTRAINT ck_household_invitations_role_position CHECK ((role <> 'viewer' OR financial_position IS NULL) AND (role <> 'financial_member' OR financial_position IS NOT NULL)),
    CONSTRAINT ck_household_invitations_expires CHECK (expires_at > created_at),
    CONSTRAINT ck_household_invitations_status CHECK (status IN ('pending','accepted','cancelled','expired')),
    CONSTRAINT ck_household_invitations_acceptance CHECK ((status = 'accepted' AND accepted_at IS NOT NULL AND accepted_by_user_id IS NOT NULL AND accepted_at >= created_at AND accepted_at < expires_at) OR (status <> 'accepted' AND accepted_at IS NULL AND accepted_by_user_id IS NULL)),
    CONSTRAINT ck_household_invitations_cancellation CHECK ((status = 'cancelled' AND cancelled_at IS NOT NULL AND cancelled_by_user_id IS NOT NULL AND cancelled_at >= created_at) OR (status <> 'cancelled' AND cancelled_at IS NULL AND cancelled_by_user_id IS NULL)),
    CONSTRAINT fk_household_invitations_household FOREIGN KEY (household_id)
        REFERENCES household.households (id) ON DELETE RESTRICT,
    CONSTRAINT fk_household_invitations_created_by FOREIGN KEY (created_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_household_invitations_accepted_by FOREIGN KEY (accepted_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_household_invitations_cancelled_by FOREIGN KEY (cancelled_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT
);

COMMENT ON TABLE household.household_invitations IS 'Convite de uso único; guarda hash do token, nunca o token em claro.';

CREATE UNIQUE INDEX ix_household_invitations_pending_email ON household.household_invitations (household_id, normalized_email) WHERE status = 'pending';

CREATE INDEX ix_household_invitations_expiration ON household.household_invitations (expires_at) WHERE status = 'pending';

CREATE INDEX ix_household_invitations_fk_household ON household.household_invitations (household_id);

CREATE INDEX ix_household_invitations_fk_created_by ON household.household_invitations (created_by_user_id);

CREATE INDEX ix_household_invitations_fk_accepted_by ON household.household_invitations (accepted_by_user_id);

CREATE INDEX ix_household_invitations_fk_cancelled_by ON household.household_invitations (cancelled_by_user_id);

CREATE TABLE household.idempotency_records (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actor_user_id uuid NOT NULL,
    operation varchar(100) NOT NULL,
    idempotency_key varchar(200) NOT NULL,
    request_hash bytea NOT NULL,
    status varchar(16) NOT NULL DEFAULT 'in_progress',
    response_status smallint,
    response_payload jsonb,
    completed_at timestamptz,
    expires_at timestamptz NOT NULL,
    CONSTRAINT pk_idempotency_records PRIMARY KEY (id),
    CONSTRAINT uq_idempotency_records_household_id_actor_user_id_oper_b7d4f5fc UNIQUE (household_id, actor_user_id, operation, idempotency_key),
    CONSTRAINT ck_idempotency_records_key CHECK (btrim(operation) <> '' AND btrim(idempotency_key) <> ''),
    CONSTRAINT ck_idempotency_records_hash CHECK (octet_length(request_hash) = 32),
    CONSTRAINT ck_idempotency_records_status CHECK (status IN ('in_progress','succeeded','failed')),
    CONSTRAINT ck_idempotency_records_expiry CHECK (expires_at > created_at),
    CONSTRAINT ck_idempotency_records_result CHECK ((status = 'in_progress' AND completed_at IS NULL AND response_status IS NULL AND response_payload IS NULL) OR (status IN ('succeeded','failed') AND completed_at IS NOT NULL AND completed_at >= created_at AND response_status IS NOT NULL AND response_status BETWEEN 100 AND 599)),
    CONSTRAINT fk_idempotency_records_household FOREIGN KEY (household_id)
        REFERENCES household.households (id) ON DELETE RESTRICT,
    CONSTRAINT fk_idempotency_records_actor FOREIGN KEY (actor_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT
);

COMMENT ON TABLE household.idempotency_records IS 'Controle de retries síncronos; fingerprint e resposta nunca devem conter credenciais.';

CREATE INDEX ix_idempotency_records_expiration ON household.idempotency_records (expires_at);

CREATE INDEX ix_idempotency_records_fk_actor ON household.idempotency_records (actor_user_id);

CREATE TABLE household.audit_logs (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL,
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
    CONSTRAINT fk_audit_logs_household FOREIGN KEY (household_id)
        REFERENCES household.households (id) ON DELETE RESTRICT,
    CONSTRAINT fk_audit_logs_actor FOREIGN KEY (actor_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT
);

COMMENT ON TABLE household.audit_logs IS 'Trilha de metadados; valores financeiros ficam nas revisões protegidas, nunca em logs operacionais.';

CREATE INDEX ix_audit_logs_history ON household.audit_logs (household_id, created_at);

CREATE INDEX ix_audit_logs_entity ON household.audit_logs (household_id, entity_type, entity_id, created_at);

CREATE INDEX ix_audit_logs_fk_actor ON household.audit_logs (actor_user_id);
