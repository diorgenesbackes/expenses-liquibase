-- PostgreSQL 17+ | Sprint 1 | 004-create-finance

CREATE TABLE finance.monthly_periods (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reference_month date NOT NULL,
    status varchar(12) NOT NULL DEFAULT 'draft',
    edit_version bigint NOT NULL DEFAULT 1,
    created_by_user_id uuid NOT NULL,
    latest_closed_version_id uuid,
    lock_owner_member_id uuid,
    lock_token uuid,
    lock_expires_at timestamptz,
    last_reopened_at timestamptz,
    last_reopened_by_user_id uuid,
    CONSTRAINT pk_monthly_periods PRIMARY KEY (id),
    CONSTRAINT uq_monthly_periods_household_id_reference_month UNIQUE (household_id, reference_month),
    CONSTRAINT uq_monthly_periods_household_id_id UNIQUE (household_id, id),
    CONSTRAINT ck_monthly_periods_month CHECK (isfinite(reference_month) AND extract(day FROM reference_month) = 1),
    CONSTRAINT ck_monthly_periods_status CHECK (status IN ('draft','closed')),
    CONSTRAINT ck_monthly_periods_version CHECK (edit_version > 0),
    CONSTRAINT ck_monthly_periods_closure CHECK (status <> 'closed' OR latest_closed_version_id IS NOT NULL),
    CONSTRAINT ck_monthly_periods_lock CHECK ((lock_owner_member_id IS NULL AND lock_token IS NULL AND lock_expires_at IS NULL) OR (lock_owner_member_id IS NOT NULL AND lock_token IS NOT NULL AND lock_expires_at IS NOT NULL)),
    CONSTRAINT ck_monthly_periods_reopening CHECK ((last_reopened_at IS NULL) = (last_reopened_by_user_id IS NULL)),
    CONSTRAINT fk_monthly_periods_household FOREIGN KEY (household_id)
        REFERENCES household.households (id) ON DELETE RESTRICT,
    CONSTRAINT fk_monthly_periods_created_by FOREIGN KEY (created_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_monthly_periods_last_reopened_by FOREIGN KEY (last_reopened_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_monthly_periods_lock_owner FOREIGN KEY (household_id, lock_owner_member_id)
        REFERENCES household.household_members (household_id, id) ON DELETE RESTRICT
);

COMMENT ON TABLE finance.monthly_periods IS 'Estado atual da competência; edit_version é independente do número de fechamento.';

CREATE INDEX ix_monthly_periods_fk_lock_owner ON finance.monthly_periods (household_id, lock_owner_member_id);

CREATE INDEX ix_monthly_periods_fk_created_by ON finance.monthly_periods (created_by_user_id);

CREATE INDEX ix_monthly_periods_fk_last_reopened_by ON finance.monthly_periods (last_reopened_by_user_id);

CREATE TABLE finance.expense_categories (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    name varchar(160) NOT NULL,
    normalized_name varchar(160) GENERATED ALWAYS AS (lower(btrim(name))) STORED,
    is_active boolean NOT NULL DEFAULT true,
    is_recurring boolean NOT NULL DEFAULT false,
    created_by_user_id uuid,
    updated_by_user_id uuid,
    CONSTRAINT pk_expense_categories PRIMARY KEY (id),
    CONSTRAINT uq_expense_categories_household_id_normalized_name UNIQUE (household_id, normalized_name),
    CONSTRAINT uq_expense_categories_household_id_id UNIQUE (household_id, id),
    CONSTRAINT ck_expense_categories_name CHECK (btrim(name) <> ''),
    CONSTRAINT fk_expense_categories_household FOREIGN KEY (household_id)
        REFERENCES household.households (id) ON DELETE RESTRICT,
    CONSTRAINT fk_expense_categories_created_by FOREIGN KEY (created_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_expense_categories_updated_by FOREIGN KEY (updated_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT
);

COMMENT ON TABLE finance.expense_categories IS 'Cadastro estável da categoria; desativação não altera meses anteriores.';

CREATE INDEX ix_expense_categories_fk_created_by ON finance.expense_categories (created_by_user_id);

CREATE INDEX ix_expense_categories_fk_updated_by ON finance.expense_categories (updated_by_user_id);

CREATE TABLE finance.period_categories (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    monthly_period_id uuid NOT NULL,
    expense_category_id uuid NOT NULL,
    name_snapshot varchar(160) NOT NULL,
    is_recurring_snapshot boolean NOT NULL DEFAULT false,
    payment_status varchar(12) NOT NULL DEFAULT 'pending',
    paid_at timestamptz,
    paid_by_user_id uuid,
    CONSTRAINT pk_period_categories PRIMARY KEY (id),
    CONSTRAINT uq_period_categories_household_id_monthly_period_id_ex_29cbee3c UNIQUE (household_id, monthly_period_id, expense_category_id),
    CONSTRAINT uq_period_categories_household_id_monthly_period_id_id UNIQUE (household_id, monthly_period_id, id),
    CONSTRAINT ck_period_categories_name CHECK (btrim(name_snapshot) <> ''),
    CONSTRAINT ck_period_categories_payment CHECK ((payment_status = 'pending' AND paid_at IS NULL AND paid_by_user_id IS NULL) OR (payment_status = 'paid' AND paid_at IS NOT NULL AND paid_by_user_id IS NOT NULL)),
    CONSTRAINT fk_period_categories_household FOREIGN KEY (household_id)
        REFERENCES household.households (id) ON DELETE RESTRICT,
    CONSTRAINT fk_period_categories_period FOREIGN KEY (household_id, monthly_period_id)
        REFERENCES finance.monthly_periods (household_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_period_categories_paid_by FOREIGN KEY (paid_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_period_categories_category FOREIGN KEY (household_id, expense_category_id)
        REFERENCES finance.expense_categories (household_id, id) ON DELETE RESTRICT
);

COMMENT ON TABLE finance.period_categories IS 'Categoria aplicada ao mês; pagamento é único para a categoria no período.';

CREATE INDEX ix_period_categories_fk_category ON finance.period_categories (household_id, expense_category_id);

CREATE INDEX ix_period_categories_fk_paid_by ON finance.period_categories (paid_by_user_id);

CREATE TABLE finance.expense_entries (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    monthly_period_id uuid NOT NULL,
    period_category_id uuid NOT NULL,
    amount numeric(18,2) NOT NULL,
    note varchar(2000),
    input_expression varchar(1000),
    created_by_user_id uuid,
    updated_by_user_id uuid,
    CONSTRAINT pk_expense_entries PRIMARY KEY (id),
    CONSTRAINT ck_expense_entries_amount CHECK (amount >= 0 AND amount <> 'NaN'::numeric),
    CONSTRAINT fk_expense_entries_household FOREIGN KEY (household_id)
        REFERENCES household.households (id) ON DELETE RESTRICT,
    CONSTRAINT fk_expense_entries_period FOREIGN KEY (household_id, monthly_period_id)
        REFERENCES finance.monthly_periods (household_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_expense_entries_created_by FOREIGN KEY (created_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_expense_entries_updated_by FOREIGN KEY (updated_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_expense_entries_period_category FOREIGN KEY (household_id, monthly_period_id, period_category_id)
        REFERENCES finance.period_categories (household_id, monthly_period_id, id) ON DELETE RESTRICT
);

COMMENT ON TABLE finance.expense_entries IS 'Lançamentos individuais; categorias sem lançamentos não geram pendência.';

CREATE INDEX ix_expense_entries_fk_period_category ON finance.expense_entries (household_id, monthly_period_id, period_category_id);

CREATE INDEX ix_expense_entries_fk_created_by ON finance.expense_entries (created_by_user_id);

CREATE INDEX ix_expense_entries_fk_updated_by ON finance.expense_entries (updated_by_user_id);

CREATE TABLE finance.period_participants (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    monthly_period_id uuid NOT NULL,
    household_member_id uuid NOT NULL,
    financial_position smallint NOT NULL,
    display_name_snapshot varchar(320) NOT NULL,
    CONSTRAINT pk_period_participants PRIMARY KEY (id),
    CONSTRAINT uq_period_participants_household_id_monthly_period_id__dd9427e3 UNIQUE (household_id, monthly_period_id, household_member_id),
    CONSTRAINT uq_period_participants_household_id_monthly_period_id__71a5c112 UNIQUE (household_id, monthly_period_id, financial_position),
    CONSTRAINT uq_period_participants_household_id_monthly_period_id_id UNIQUE (household_id, monthly_period_id, id),
    CONSTRAINT ck_period_participants_position CHECK (financial_position IN (1,2)),
    CONSTRAINT ck_period_participants_display_name CHECK (btrim(display_name_snapshot) <> ''),
    CONSTRAINT fk_period_participants_household FOREIGN KEY (household_id)
        REFERENCES household.households (id) ON DELETE RESTRICT,
    CONSTRAINT fk_period_participants_period FOREIGN KEY (household_id, monthly_period_id)
        REFERENCES finance.monthly_periods (household_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_period_participants_member FOREIGN KEY (household_id, household_member_id)
        REFERENCES household.household_members (household_id, id) ON DELETE RESTRICT
);

COMMENT ON TABLE finance.period_participants IS 'Responsáveis preservados na competência, independentemente do vínculo atual.';

CREATE INDEX ix_period_participants_fk_member ON finance.period_participants (household_id, household_member_id);

CREATE TABLE finance.salary_entries (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    monthly_period_id uuid NOT NULL,
    period_participant_id uuid NOT NULL,
    amount numeric(18,2) NOT NULL,
    created_by_user_id uuid,
    updated_by_user_id uuid,
    CONSTRAINT pk_salary_entries PRIMARY KEY (id),
    CONSTRAINT uq_salary_entries_household_id_monthly_period_id_perio_908744de UNIQUE (household_id, monthly_period_id, period_participant_id),
    CONSTRAINT ck_salary_entries_amount CHECK (amount >= 0 AND amount <> 'NaN'::numeric),
    CONSTRAINT fk_salary_entries_household FOREIGN KEY (household_id)
        REFERENCES household.households (id) ON DELETE RESTRICT,
    CONSTRAINT fk_salary_entries_period FOREIGN KEY (household_id, monthly_period_id)
        REFERENCES finance.monthly_periods (household_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_salary_entries_created_by FOREIGN KEY (created_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_salary_entries_updated_by FOREIGN KEY (updated_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_salary_entries_participant FOREIGN KEY (household_id, monthly_period_id, period_participant_id)
        REFERENCES finance.period_participants (household_id, monthly_period_id, id) ON DELETE RESTRICT
);

COMMENT ON TABLE finance.salary_entries IS 'Salário líquido; ausência de linha difere de valor zero.';

CREATE INDEX ix_salary_entries_fk_created_by ON finance.salary_entries (created_by_user_id);

CREATE INDEX ix_salary_entries_fk_updated_by ON finance.salary_entries (updated_by_user_id);

CREATE TABLE finance.benefits (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    name varchar(160) NOT NULL,
    normalized_name varchar(160) GENERATED ALWAYS AS (lower(btrim(name))) STORED,
    owner_member_id uuid,
    is_active boolean NOT NULL DEFAULT true,
    application_order integer NOT NULL,
    created_by_user_id uuid,
    updated_by_user_id uuid,
    CONSTRAINT pk_benefits PRIMARY KEY (id),
    CONSTRAINT uq_benefits_household_id_normalized_name UNIQUE (household_id, normalized_name),
    CONSTRAINT uq_benefits_household_id_id UNIQUE (household_id, id),
    CONSTRAINT ck_benefits_name CHECK (btrim(name) <> ''),
    CONSTRAINT ck_benefits_order CHECK (application_order > 0),
    CONSTRAINT fk_benefits_household FOREIGN KEY (household_id)
        REFERENCES household.households (id) ON DELETE RESTRICT,
    CONSTRAINT fk_benefits_created_by FOREIGN KEY (created_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_benefits_updated_by FOREIGN KEY (updated_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_benefits_owner FOREIGN KEY (household_id, owner_member_id)
        REFERENCES household.household_members (household_id, id) ON DELETE RESTRICT
);

COMMENT ON TABLE finance.benefits IS 'Benefício e ordem padrão; alterações são copiadas somente para períodos aplicáveis.';

CREATE UNIQUE INDEX ix_benefits_active_order ON finance.benefits (household_id, application_order) WHERE is_active;

CREATE INDEX ix_benefits_fk_owner ON finance.benefits (household_id, owner_member_id);

CREATE INDEX ix_benefits_fk_created_by ON finance.benefits (created_by_user_id);

CREATE INDEX ix_benefits_fk_updated_by ON finance.benefits (updated_by_user_id);

CREATE TABLE finance.benefit_priorities (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    benefit_id uuid NOT NULL,
    household_member_id uuid NOT NULL,
    priority smallint NOT NULL,
    CONSTRAINT pk_benefit_priorities PRIMARY KEY (id),
    CONSTRAINT uq_benefit_priorities_household_id_benefit_id_priority UNIQUE (household_id, benefit_id, priority),
    CONSTRAINT uq_benefit_priorities_household_id_benefit_id_househol_ef624b76 UNIQUE (household_id, benefit_id, household_member_id),
    CONSTRAINT ck_benefit_priorities_priority CHECK (priority IN (1,2)),
    CONSTRAINT fk_benefit_priorities_household FOREIGN KEY (household_id)
        REFERENCES household.households (id) ON DELETE RESTRICT,
    CONSTRAINT fk_benefit_priorities_benefit FOREIGN KEY (household_id, benefit_id)
        REFERENCES finance.benefits (household_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_benefit_priorities_member FOREIGN KEY (household_id, household_member_id)
        REFERENCES household.household_members (household_id, id) ON DELETE RESTRICT
);

COMMENT ON TABLE finance.benefit_priorities IS 'Prioridade padrão entre membros; cópia mensal é a fonte usada no rateio.';

CREATE INDEX ix_benefit_priorities_fk_member ON finance.benefit_priorities (household_id, household_member_id);

CREATE TABLE finance.benefit_entries (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    monthly_period_id uuid NOT NULL,
    benefit_id uuid NOT NULL,
    name_snapshot varchar(160) NOT NULL,
    application_order integer NOT NULL,
    amount numeric(18,2) NOT NULL,
    created_by_user_id uuid,
    updated_by_user_id uuid,
    CONSTRAINT pk_benefit_entries PRIMARY KEY (id),
    CONSTRAINT uq_benefit_entries_household_id_monthly_period_id_benefit_id UNIQUE (household_id, monthly_period_id, benefit_id),
    CONSTRAINT uq_benefit_entries_household_id_monthly_period_id_appl_bde48c63 UNIQUE (household_id, monthly_period_id, application_order),
    CONSTRAINT uq_benefit_entries_household_id_monthly_period_id_id UNIQUE (household_id, monthly_period_id, id),
    CONSTRAINT ck_benefit_entries_amount CHECK (amount >= 0 AND amount <> 'NaN'::numeric),
    CONSTRAINT ck_benefit_entries_order CHECK (application_order > 0),
    CONSTRAINT ck_benefit_entries_name CHECK (btrim(name_snapshot) <> ''),
    CONSTRAINT fk_benefit_entries_household FOREIGN KEY (household_id)
        REFERENCES household.households (id) ON DELETE RESTRICT,
    CONSTRAINT fk_benefit_entries_period FOREIGN KEY (household_id, monthly_period_id)
        REFERENCES finance.monthly_periods (household_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_benefit_entries_created_by FOREIGN KEY (created_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_benefit_entries_updated_by FOREIGN KEY (updated_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_benefit_entries_benefit FOREIGN KEY (household_id, benefit_id)
        REFERENCES finance.benefits (household_id, id) ON DELETE RESTRICT
);

COMMENT ON TABLE finance.benefit_entries IS 'Valor e ordem efetivos do benefício no mês.';

CREATE INDEX ix_benefit_entries_fk_benefit ON finance.benefit_entries (household_id, benefit_id);

CREATE INDEX ix_benefit_entries_fk_created_by ON finance.benefit_entries (created_by_user_id);

CREATE INDEX ix_benefit_entries_fk_updated_by ON finance.benefit_entries (updated_by_user_id);

CREATE TABLE finance.period_benefit_priorities (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    monthly_period_id uuid NOT NULL,
    benefit_entry_id uuid NOT NULL,
    period_participant_id uuid NOT NULL,
    priority smallint NOT NULL,
    CONSTRAINT pk_period_benefit_priorities PRIMARY KEY (id),
    CONSTRAINT uq_period_benefit_priorities_household_id_benefit_entr_6a6b43cc UNIQUE (household_id, benefit_entry_id, priority),
    CONSTRAINT uq_period_benefit_priorities_household_id_benefit_entr_a75b7f74 UNIQUE (household_id, benefit_entry_id, period_participant_id),
    CONSTRAINT ck_period_benefit_priorities_priority CHECK (priority IN (1,2)),
    CONSTRAINT fk_period_benefit_priorities_household FOREIGN KEY (household_id)
        REFERENCES household.households (id) ON DELETE RESTRICT,
    CONSTRAINT fk_period_benefit_priorities_period FOREIGN KEY (household_id, monthly_period_id)
        REFERENCES finance.monthly_periods (household_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_period_benefit_priorities_benefit FOREIGN KEY (household_id, monthly_period_id, benefit_entry_id)
        REFERENCES finance.benefit_entries (household_id, monthly_period_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_period_benefit_priorities_participant FOREIGN KEY (household_id, monthly_period_id, period_participant_id)
        REFERENCES finance.period_participants (household_id, monthly_period_id, id) ON DELETE RESTRICT
);

COMMENT ON TABLE finance.period_benefit_priorities IS 'Prioridade mensal com FKs que exigem benefício e participante do mesmo mês.';

CREATE INDEX ix_period_benefit_priorities_fk_benefit ON finance.period_benefit_priorities (household_id, monthly_period_id, benefit_entry_id);

CREATE INDEX ix_period_benefit_priorities_fk_participant ON finance.period_benefit_priorities (household_id, monthly_period_id, period_participant_id);
