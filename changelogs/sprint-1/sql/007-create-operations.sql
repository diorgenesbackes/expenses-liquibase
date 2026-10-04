-- PostgreSQL 17+ | Sprint 1 | 007-create-operations

CREATE TABLE finance.migration_records (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by_user_id uuid NOT NULL,
    source_namespace varchar(160) NOT NULL,
    format_version varchar(32) NOT NULL,
    file_checksum bytea NOT NULL,
    batch_number integer NOT NULL DEFAULT 1,
    status varchar(16) NOT NULL,
    started_at timestamptz NOT NULL,
    completed_at timestamptz NOT NULL,
    record_count integer NOT NULL,
    imported_count integer NOT NULL,
    rejected_count integer NOT NULL,
    error_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT pk_migration_records PRIMARY KEY (id),
    CONSTRAINT uq_migration_records_household_id_id_source_namespace UNIQUE (household_id, id, source_namespace),
    CONSTRAINT ck_migration_records_checksum CHECK (octet_length(file_checksum) = 32),
    CONSTRAINT ck_migration_records_status CHECK (status IN ('completed','failed')),
    CONSTRAINT ck_migration_records_counts CHECK (batch_number > 0 AND record_count >= 0 AND imported_count >= 0 AND rejected_count >= 0 AND imported_count + rejected_count <= record_count),
    CONSTRAINT ck_migration_records_dates CHECK (completed_at >= started_at),
    CONSTRAINT ck_migration_records_errors CHECK (jsonb_typeof(error_summary) = 'object'),
    CONSTRAINT fk_migration_records_household FOREIGN KEY (household_id)
        REFERENCES household.households (id) ON DELETE RESTRICT,
    CONSTRAINT fk_migration_records_created_by FOREIGN KEY (created_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT
);

COMMENT ON TABLE finance.migration_records IS 'Resultado da importação histórica síncrona por arquivo/lote; não representa job.';

CREATE UNIQUE INDEX ix_migration_records_completed_batch ON finance.migration_records (household_id, source_namespace, file_checksum, batch_number) WHERE status = 'completed';

CREATE INDEX ix_migration_records_fk_created_by ON finance.migration_records (created_by_user_id);

CREATE TABLE finance.migration_items (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    migration_record_id uuid NOT NULL,
    source_namespace varchar(160) NOT NULL,
    source_entity_type varchar(64) NOT NULL,
    source_record_key varchar(240) NOT NULL,
    target_entity_type varchar(64) NOT NULL,
    target_entity_id uuid NOT NULL,
    CONSTRAINT pk_migration_items PRIMARY KEY (id),
    CONSTRAINT uq_migration_items_household_id_source_namespace_sourc_f0d57561 UNIQUE (household_id, source_namespace, source_entity_type, source_record_key),
    CONSTRAINT ck_migration_items_source CHECK (btrim(source_namespace) <> '' AND btrim(source_entity_type) <> '' AND btrim(source_record_key) <> ''),
    CONSTRAINT ck_migration_items_target CHECK (target_entity_type IN ('monthly_period','expense_category','expense_entry','salary_entry','benefit','benefit_entry','income_source','income_entry')),
    CONSTRAINT fk_migration_items_household FOREIGN KEY (household_id)
        REFERENCES household.households (id) ON DELETE RESTRICT,
    CONSTRAINT fk_migration_items_migration FOREIGN KEY (household_id, migration_record_id, source_namespace)
        REFERENCES finance.migration_records (household_id, id, source_namespace) ON DELETE RESTRICT
);

COMMENT ON TABLE finance.migration_items IS 'Mapa histórico de origem; o destino lógico pode ter sido removido após a importação.';

CREATE INDEX ix_migration_items_target ON finance.migration_items (household_id, target_entity_type, target_entity_id);

CREATE INDEX ix_migration_items_fk_migration ON finance.migration_items (household_id, migration_record_id, source_namespace);

CREATE TABLE finance.export_records (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by_user_id uuid NOT NULL,
    format varchar(16) NOT NULL,
    format_version varchar(32) NOT NULL,
    filters jsonb NOT NULL DEFAULT '{}'::jsonb,
    status varchar(16) NOT NULL,
    started_at timestamptz NOT NULL,
    completed_at timestamptz NOT NULL,
    record_count integer NOT NULL DEFAULT 0,
    content_checksum bytea,
    failure_code varchar(100),
    CONSTRAINT pk_export_records PRIMARY KEY (id),
    CONSTRAINT ck_export_records_format CHECK (format IN ('json','csv')),
    CONSTRAINT ck_export_records_status CHECK (status IN ('completed','failed')),
    CONSTRAINT ck_export_records_dates CHECK (completed_at >= started_at),
    CONSTRAINT ck_export_records_count CHECK (record_count >= 0),
    CONSTRAINT ck_export_records_checksum CHECK (content_checksum IS NULL OR octet_length(content_checksum) = 32),
    CONSTRAINT ck_export_records_filters CHECK (jsonb_typeof(filters) = 'object'),
    CONSTRAINT fk_export_records_household FOREIGN KEY (household_id)
        REFERENCES household.households (id) ON DELETE RESTRICT,
    CONSTRAINT fk_export_records_created_by FOREIGN KEY (created_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT
);

COMMENT ON TABLE finance.export_records IS 'Resultado da geração síncrona; não comprova download pelo usuário.';

CREATE INDEX ix_export_records_history ON finance.export_records (household_id, created_at);

CREATE INDEX ix_export_records_fk_created_by ON finance.export_records (created_by_user_id);

CREATE TABLE finance.entry_revisions (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    monthly_period_id uuid NOT NULL,
    entity_type varchar(64) NOT NULL,
    entity_id uuid NOT NULL,
    operation varchar(12) NOT NULL,
    period_edit_version bigint NOT NULL,
    created_by_user_id uuid NOT NULL,
    before_data jsonb,
    after_data jsonb,
    correlation_id uuid,
    CONSTRAINT pk_entry_revisions PRIMARY KEY (id),
    CONSTRAINT ck_entry_revisions_operation CHECK (operation IN ('insert','update','delete')),
    CONSTRAINT ck_entry_revisions_version CHECK (period_edit_version > 0),
    CONSTRAINT ck_entry_revisions_images CHECK ((operation = 'insert' AND before_data IS NULL AND after_data IS NOT NULL) OR (operation = 'update' AND before_data IS NOT NULL AND after_data IS NOT NULL) OR (operation = 'delete' AND before_data IS NOT NULL AND after_data IS NULL)),
    CONSTRAINT ck_entry_revisions_json CHECK ((before_data IS NULL OR jsonb_typeof(before_data) = 'object') AND (after_data IS NULL OR jsonb_typeof(after_data) = 'object')),
    CONSTRAINT fk_entry_revisions_household FOREIGN KEY (household_id)
        REFERENCES household.households (id) ON DELETE RESTRICT,
    CONSTRAINT fk_entry_revisions_period FOREIGN KEY (household_id, monthly_period_id)
        REFERENCES finance.monthly_periods (household_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_entry_revisions_created_by FOREIGN KEY (created_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT
);

COMMENT ON TABLE finance.entry_revisions IS 'Revisões protegidas de dados financeiros; referências lógicas sobrevivem à remoção de lançamentos.';

CREATE INDEX ix_entry_revisions_entity_history ON finance.entry_revisions (household_id, entity_type, entity_id, created_at);

CREATE INDEX ix_entry_revisions_fk_period ON finance.entry_revisions (household_id, monthly_period_id);

CREATE INDEX ix_entry_revisions_fk_created_by ON finance.entry_revisions (created_by_user_id);

CREATE TABLE finance.idempotency_records (
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

COMMENT ON TABLE finance.idempotency_records IS 'Controle de retries síncronos; fingerprint e resposta nunca devem conter credenciais.';

CREATE INDEX ix_idempotency_records_expiration ON finance.idempotency_records (expires_at);

CREATE INDEX ix_idempotency_records_fk_actor ON finance.idempotency_records (actor_user_id);

CREATE TABLE finance.audit_logs (
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

COMMENT ON TABLE finance.audit_logs IS 'Trilha de metadados; valores financeiros ficam nas revisões protegidas, nunca em logs operacionais.';

CREATE INDEX ix_audit_logs_history ON finance.audit_logs (household_id, created_at);

CREATE INDEX ix_audit_logs_entity ON finance.audit_logs (household_id, entity_type, entity_id, created_at);

CREATE INDEX ix_audit_logs_fk_actor ON finance.audit_logs (actor_user_id);
