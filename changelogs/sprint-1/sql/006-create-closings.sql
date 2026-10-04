-- PostgreSQL 17+ | Sprint 1 | 006-create-closings

CREATE TABLE finance.monthly_period_versions (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    monthly_period_id uuid NOT NULL,
    closing_number integer NOT NULL,
    source_edit_version bigint NOT NULL,
    closed_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    closed_by_user_id uuid NOT NULL,
    snapshot_schema_version integer NOT NULL DEFAULT 1,
    snapshot jsonb NOT NULL,
    CONSTRAINT pk_monthly_period_versions PRIMARY KEY (id),
    CONSTRAINT uq_monthly_period_versions_household_id_monthly_period_dca9734d UNIQUE (household_id, monthly_period_id, closing_number),
    CONSTRAINT uq_monthly_period_versions_household_id_monthly_period_id_id UNIQUE (household_id, monthly_period_id, id),
    CONSTRAINT uq_monthly_period_versions_household_id_id UNIQUE (household_id, id),
    CONSTRAINT ck_monthly_period_versions_versions CHECK (closing_number > 0 AND source_edit_version > 0 AND snapshot_schema_version > 0),
    CONSTRAINT ck_monthly_period_versions_snapshot CHECK (jsonb_typeof(snapshot) = 'object' AND jsonb_exists_all(snapshot, ARRAY['categories','expenses','payments','participants','salaries','benefits','benefit_priorities','income_sources','incomes']) AND jsonb_typeof(snapshot -> 'categories') = 'array' AND jsonb_typeof(snapshot -> 'expenses') = 'array' AND jsonb_typeof(snapshot -> 'payments') = 'array' AND jsonb_typeof(snapshot -> 'participants') = 'array' AND jsonb_typeof(snapshot -> 'salaries') = 'array' AND jsonb_typeof(snapshot -> 'benefits') = 'array' AND jsonb_typeof(snapshot -> 'benefit_priorities') = 'array' AND jsonb_typeof(snapshot -> 'income_sources') = 'array' AND jsonb_typeof(snapshot -> 'incomes') = 'array'),
    CONSTRAINT fk_monthly_period_versions_household FOREIGN KEY (household_id)
        REFERENCES household.households (id) ON DELETE RESTRICT,
    CONSTRAINT fk_monthly_period_versions_period FOREIGN KEY (household_id, monthly_period_id)
        REFERENCES finance.monthly_periods (household_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_monthly_period_versions_closed_by FOREIGN KEY (closed_by_user_id)
        REFERENCES identity.users (id) ON DELETE RESTRICT
);

COMMENT ON TABLE finance.monthly_period_versions IS 'Snapshot completo imutável do mês; cada fechamento recebe novo número.';

CREATE INDEX ix_monthly_period_versions_fk_closed_by ON finance.monthly_period_versions (closed_by_user_id);

CREATE TABLE finance.allocation_snapshots (
    id uuid NOT NULL,
    household_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    commitment_percentage integer NOT NULL,
    cost_total numeric(18,2) NOT NULL,
    salary_total numeric(18,2) NOT NULL,
    benefit_total numeric(18,2) NOT NULL,
    benefit_applied numeric(18,2) NOT NULL,
    cash_total numeric(18,2) NOT NULL,
    total_committed numeric(18,2) NOT NULL,
    difference numeric(18,2) GENERATED ALWAYS AS (total_committed - cost_total) STORED,
    benefit_excess numeric(18,2) GENERATED ALWAYS AS (benefit_total - benefit_applied) STORED,
    currency_code varchar(3) NOT NULL DEFAULT 'BRL',
    algorithm_version varchar(64) NOT NULL,
    rounding_policy varchar(64) NOT NULL,
    snapshot_schema_version integer NOT NULL DEFAULT 1,
    participants jsonb NOT NULL,
    benefit_applications jsonb NOT NULL,
    CONSTRAINT pk_allocation_snapshots PRIMARY KEY (id),
    CONSTRAINT uq_allocation_snapshots_household_id_id UNIQUE (household_id, id),
    CONSTRAINT ck_allocation_snapshots_cost_total CHECK (cost_total >= 0 AND cost_total <> 'NaN'::numeric),
    CONSTRAINT ck_allocation_snapshots_salary_total CHECK (salary_total >= 0 AND salary_total <> 'NaN'::numeric),
    CONSTRAINT ck_allocation_snapshots_benefit_total CHECK (benefit_total >= 0 AND benefit_total <> 'NaN'::numeric),
    CONSTRAINT ck_allocation_snapshots_benefit_applied CHECK (benefit_applied >= 0 AND benefit_applied <> 'NaN'::numeric),
    CONSTRAINT ck_allocation_snapshots_cash_total CHECK (cash_total >= 0 AND cash_total <> 'NaN'::numeric),
    CONSTRAINT ck_allocation_snapshots_total_committed CHECK (total_committed >= 0 AND total_committed <> 'NaN'::numeric),
    CONSTRAINT ck_allocation_snapshots_percentage CHECK (commitment_percentage >= 0),
    CONSTRAINT ck_allocation_snapshots_totals CHECK (benefit_applied <= benefit_total AND total_committed = cash_total + benefit_applied AND total_committed >= cost_total),
    CONSTRAINT ck_allocation_snapshots_currency CHECK (currency_code = 'BRL'),
    CONSTRAINT ck_allocation_snapshots_algorithm CHECK (btrim(algorithm_version) <> '' AND btrim(rounding_policy) <> '' AND snapshot_schema_version > 0),
    CONSTRAINT ck_allocation_snapshots_participants CHECK (jsonb_typeof(participants) = 'array' AND jsonb_array_length(participants) BETWEEN 1 AND 2),
    CONSTRAINT ck_allocation_snapshots_applications CHECK (jsonb_typeof(benefit_applications) = 'array'),
    CONSTRAINT fk_allocation_snapshots_household FOREIGN KEY (household_id)
        REFERENCES household.households (id) ON DELETE RESTRICT,
    CONSTRAINT fk_allocation_snapshots_period_version FOREIGN KEY (household_id, id)
        REFERENCES finance.monthly_period_versions (household_id, id) ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED
);

COMMENT ON TABLE finance.allocation_snapshots IS 'Rateio imutável; id compartilhado com a versão do período. Detalhamento em JSON versionado.';

ALTER TABLE finance.monthly_period_versions ADD CONSTRAINT fk_period_version_required_allocation FOREIGN KEY (household_id, id) REFERENCES finance.allocation_snapshots (household_id, id) ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE finance.monthly_periods ADD CONSTRAINT fk_period_latest_closed_version FOREIGN KEY (household_id, id, latest_closed_version_id) REFERENCES finance.monthly_period_versions (household_id, monthly_period_id, id) ON DELETE RESTRICT;

CREATE INDEX ix_periods_latest_closed_version ON finance.monthly_periods (household_id, id, latest_closed_version_id);
