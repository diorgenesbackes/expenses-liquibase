-- PostgreSQL 17+ | Sprint 1 | 005-create-income

CREATE TABLE income.income_sources (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    name varchar(160) NOT NULL,
    normalized_name varchar(160) GENERATED ALWAYS AS (lower(btrim(name))) STORED,
    source_type varchar(16) NOT NULL DEFAULT 'other',
    is_active boolean NOT NULL DEFAULT true,
    created_by_user_id uuid,
    updated_by_user_id uuid,
    CONSTRAINT pk_income_sources PRIMARY KEY (id),
    CONSTRAINT uq_income_sources_household_id_normalized_name UNIQUE (household_id, normalized_name),
    CONSTRAINT uq_income_sources_household_id_id UNIQUE (household_id, id),
    CONSTRAINT ck_income_sources_name CHECK (btrim(name) <> ''),
    CONSTRAINT ck_income_sources_type CHECK (source_type IN ('rental','other')),
    CONSTRAINT fk_income_sources_household FOREIGN KEY (household_id)
        REFERENCES household.households (id) ON DELETE RESTRICT,
    CONSTRAINT fk_income_sources_created_by FOREIGN KEY (created_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_income_sources_updated_by FOREIGN KEY (updated_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT
);

COMMENT ON TABLE income.income_sources IS 'Fonte recorrente de renda; nome e ativação não reescrevem fechamentos.';

CREATE INDEX ix_income_sources_fk_created_by ON income.income_sources (created_by_user_id);

CREATE INDEX ix_income_sources_fk_updated_by ON income.income_sources (updated_by_user_id);

CREATE TABLE income.income_entries (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    monthly_period_id uuid NOT NULL,
    income_source_id uuid,
    entry_type varchar(16) NOT NULL,
    status varchar(16) NOT NULL DEFAULT 'confirmed',
    amount numeric(18,2) NOT NULL,
    source_name_snapshot varchar(160),
    note varchar(2000),
    input_expression varchar(1000),
    suggested_from_entry_id uuid,
    confirmed_at timestamptz,
    created_by_user_id uuid,
    updated_by_user_id uuid,
    CONSTRAINT pk_income_entries PRIMARY KEY (id),
    CONSTRAINT uq_income_entries_household_id_income_source_id_id UNIQUE (household_id, income_source_id, id),
    CONSTRAINT ck_income_entries_amount CHECK (amount >= 0 AND amount <> 'NaN'::numeric),
    CONSTRAINT ck_income_entries_type CHECK ((entry_type = 'recurring' AND income_source_id IS NOT NULL AND source_name_snapshot IS NOT NULL AND btrim(source_name_snapshot) <> '') OR (entry_type = 'variable' AND income_source_id IS NULL AND source_name_snapshot IS NULL AND suggested_from_entry_id IS NULL)),
    CONSTRAINT ck_income_entries_status CHECK ((status = 'suggested' AND entry_type = 'recurring' AND confirmed_at IS NULL) OR (status = 'confirmed' AND confirmed_at IS NOT NULL)),
    CONSTRAINT ck_income_entries_origin CHECK (suggested_from_entry_id IS NULL OR suggested_from_entry_id <> id),
    CONSTRAINT fk_income_entries_household FOREIGN KEY (household_id)
        REFERENCES household.households (id) ON DELETE RESTRICT,
    CONSTRAINT fk_income_entries_period FOREIGN KEY (household_id, monthly_period_id)
        REFERENCES finance.monthly_periods (household_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_income_entries_created_by FOREIGN KEY (created_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_income_entries_updated_by FOREIGN KEY (updated_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_income_entries_source FOREIGN KEY (household_id, income_source_id)
        REFERENCES income.income_sources (household_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_income_entries_suggestion_origin FOREIGN KEY (household_id, income_source_id, suggested_from_entry_id)
        REFERENCES income.income_entries (household_id, income_source_id, id) ON DELETE RESTRICT
);

COMMENT ON TABLE income.income_entries IS 'Renda mensal; sugestões só entram nos totais após confirmação.';

CREATE UNIQUE INDEX ix_income_entries_suggestion ON income.income_entries (household_id, monthly_period_id, income_source_id) WHERE status = 'suggested';

CREATE INDEX ix_income_entries_source_history ON income.income_entries (household_id, income_source_id, monthly_period_id);

CREATE INDEX ix_income_entries_fk_suggestion_origin ON income.income_entries (household_id, income_source_id, suggested_from_entry_id);

CREATE INDEX ix_income_entries_fk_period ON income.income_entries (household_id, monthly_period_id);

CREATE INDEX ix_income_entries_fk_created_by ON income.income_entries (created_by_user_id);

CREATE INDEX ix_income_entries_fk_updated_by ON income.income_entries (updated_by_user_id);

CREATE TABLE income.idempotency_records (
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

COMMENT ON TABLE income.idempotency_records IS 'Controle de retries síncronos; fingerprint e resposta nunca devem conter credenciais.';

CREATE INDEX ix_idempotency_records_expiration ON income.idempotency_records (expires_at);

CREATE INDEX ix_idempotency_records_fk_actor ON income.idempotency_records (actor_user_id);

CREATE TABLE income.audit_logs (
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

COMMENT ON TABLE income.audit_logs IS 'Trilha de metadados; valores financeiros ficam nas revisões protegidas, nunca em logs operacionais.';

CREATE INDEX ix_audit_logs_history ON income.audit_logs (household_id, created_at);

CREATE INDEX ix_audit_logs_entity ON income.audit_logs (household_id, entity_type, entity_id, created_at);

CREATE INDEX ix_audit_logs_fk_actor ON income.audit_logs (actor_user_id);
