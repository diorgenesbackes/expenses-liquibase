-- PostgreSQL 17+ | Sprint 1 | 008-create-integrity-guards

DROP TRIGGER tr_reset_category_payment ON finance.expense_entries;

DROP TRIGGER tr_require_open_period ON finance.monthly_period_versions;

DROP TRIGGER tr_protect_snapshot ON finance.allocation_snapshots;

DROP TRIGGER tr_protect_snapshot ON finance.monthly_period_versions;

DROP TRIGGER ct_require_active_admin ON household.household_members;

DROP TRIGGER ct_require_active_admin ON household.households;

DROP TRIGGER tr_protect_period_identity ON finance.monthly_periods;

DROP TRIGGER tr_serialize_membership ON household.household_members;

DROP TRIGGER tr_reject_history_update ON income.audit_logs;

DROP TRIGGER tr_touch_updated_at ON income.idempotency_records;

DROP TRIGGER tr_reject_history_update ON finance.audit_logs;

DROP TRIGGER tr_touch_updated_at ON finance.idempotency_records;

DROP TRIGGER tr_reject_history_update ON household.audit_logs;

DROP TRIGGER tr_touch_updated_at ON household.idempotency_records;

DROP TRIGGER tr_reject_history_update ON identity.audit_logs;

DROP TRIGGER tr_touch_updated_at ON identity.idempotency_records;

DROP TRIGGER tr_reject_history_update ON finance.entry_revisions;

DROP TRIGGER tr_reject_history_update ON finance.export_records;

DROP TRIGGER tr_reject_history_update ON finance.migration_items;

DROP TRIGGER tr_reject_history_update ON finance.migration_records;

DROP TRIGGER tr_require_open_period ON income.income_entries;

DROP TRIGGER tr_touch_updated_at ON income.income_entries;

DROP TRIGGER tr_touch_updated_at ON income.income_sources;

DROP TRIGGER tr_require_open_period ON finance.period_benefit_priorities;

DROP TRIGGER tr_touch_updated_at ON finance.period_benefit_priorities;

DROP TRIGGER tr_require_open_period ON finance.benefit_entries;

DROP TRIGGER tr_touch_updated_at ON finance.benefit_entries;

DROP TRIGGER tr_touch_updated_at ON finance.benefit_priorities;

DROP TRIGGER tr_touch_updated_at ON finance.benefits;

DROP TRIGGER tr_require_open_period ON finance.salary_entries;

DROP TRIGGER tr_touch_updated_at ON finance.salary_entries;

DROP TRIGGER tr_require_open_period ON finance.period_participants;

DROP TRIGGER tr_touch_updated_at ON finance.period_participants;

DROP TRIGGER tr_require_open_period ON finance.expense_entries;

DROP TRIGGER tr_touch_updated_at ON finance.expense_entries;

DROP TRIGGER tr_require_open_period ON finance.period_categories;

DROP TRIGGER tr_touch_updated_at ON finance.period_categories;

DROP TRIGGER tr_touch_updated_at ON finance.expense_categories;

DROP TRIGGER tr_touch_updated_at ON finance.monthly_periods;

DROP TRIGGER tr_touch_updated_at ON household.household_invitations;

DROP TRIGGER tr_touch_updated_at ON household.household_members;

DROP TRIGGER tr_touch_updated_at ON household.households;

DROP TRIGGER tr_touch_updated_at ON identity.identity_reconciliations;

DROP TRIGGER tr_touch_updated_at ON identity.login_blocks;

DROP TRIGGER tr_touch_updated_at ON identity.users;

DROP FUNCTION finance.reset_category_payment();

DROP FUNCTION finance.protect_closing_snapshot();

DROP FUNCTION finance.require_open_period();

DROP FUNCTION finance.protect_period_identity();

DROP FUNCTION household.require_active_admin();

DROP FUNCTION household.serialize_membership();

DROP FUNCTION identity.reject_history_update();

DROP FUNCTION identity.touch_updated_at();
