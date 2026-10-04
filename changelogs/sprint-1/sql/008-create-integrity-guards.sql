-- PostgreSQL 17+ | Sprint 1 | 008-create-integrity-guards

CREATE FUNCTION identity.touch_updated_at() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $fn$
BEGIN
    NEW.updated_at := statement_timestamp();
    RETURN NEW;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION identity.touch_updated_at() FROM PUBLIC;

CREATE FUNCTION identity.reject_history_update() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $fn$
BEGIN
    RAISE EXCEPTION 'Historical record in %.% cannot be updated', TG_TABLE_SCHEMA, TG_TABLE_NAME
        USING ERRCODE = '23514';
END;
$fn$;

REVOKE EXECUTE ON FUNCTION identity.reject_history_update() FROM PUBLIC;

CREATE FUNCTION household.serialize_membership() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $fn$
DECLARE target_household uuid;
BEGIN
    IF TG_OP = 'UPDATE' AND (NEW.id, NEW.household_id, NEW.user_id)
            IS DISTINCT FROM (OLD.id, OLD.household_id, OLD.user_id) THEN
        RAISE EXCEPTION 'Membership identity cannot change' USING ERRCODE = '23514';
    END IF;
    target_household := CASE WHEN TG_OP = 'DELETE' THEN OLD.household_id ELSE NEW.household_id END;
    -- An actual row update serializes membership changes even at REPEATABLE READ.
    UPDATE household.households SET membership_version = membership_version + 1
    WHERE id = target_household;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION household.serialize_membership() FROM PUBLIC;

CREATE FUNCTION household.require_active_admin() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $fn$
DECLARE target_household uuid;
BEGIN
    IF TG_TABLE_NAME = 'households' THEN
        target_household := CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END;
    ELSE
        target_household := CASE WHEN TG_OP = 'DELETE' THEN OLD.household_id ELSE NEW.household_id END;
    END IF;
    IF EXISTS (SELECT 1 FROM household.households WHERE id = target_household AND deleted_at IS NULL)
       AND NOT EXISTS (SELECT 1 FROM household.household_members
           WHERE household_id = target_household AND role = 'household_admin' AND left_at IS NULL) THEN
        RAISE EXCEPTION 'An active household requires an active administrator' USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION household.require_active_admin() FROM PUBLIC;

CREATE FUNCTION finance.protect_period_identity() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $fn$
BEGIN
    IF (NEW.id, NEW.household_id, NEW.reference_month)
            IS DISTINCT FROM (OLD.id, OLD.household_id, OLD.reference_month) THEN
        RAISE EXCEPTION 'Period identity and reference month cannot change' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION finance.protect_period_identity() FROM PUBLIC;

CREATE FUNCTION finance.require_open_period() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $fn$
DECLARE
    target_household uuid;
    target_period uuid;
    house_deleted_at timestamptz;
    recovery_deadline timestamptz;
    period_status text;
BEGIN
    IF TG_OP = 'UPDATE' AND (NEW.id, NEW.household_id, NEW.monthly_period_id)
            IS DISTINCT FROM (OLD.id, OLD.household_id, OLD.monthly_period_id) THEN
        RAISE EXCEPTION 'Monthly record identity cannot change' USING ERRCODE = '23514';
    END IF;
    target_household := CASE WHEN TG_OP = 'DELETE' THEN OLD.household_id ELSE NEW.household_id END;
    target_period := CASE WHEN TG_OP = 'DELETE' THEN OLD.monthly_period_id ELSE NEW.monthly_period_id END;
    SELECT deleted_at, recoverable_until INTO house_deleted_at, recovery_deadline
    FROM household.households WHERE id = target_household FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Household does not exist' USING ERRCODE = '23503';
    END IF;
    IF house_deleted_at IS NOT NULL THEN
        IF TG_OP = 'DELETE' AND recovery_deadline <= statement_timestamp() THEN RETURN OLD; END IF;
        RAISE EXCEPTION 'Household is deleted' USING ERRCODE = '23514';
    END IF;
    SELECT status INTO period_status FROM finance.monthly_periods
    WHERE household_id = target_household AND id = target_period FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Monthly period does not exist in household' USING ERRCODE = '23503';
    END IF;
    IF period_status <> 'draft' THEN
        RAISE EXCEPTION 'Reopen the period before changing its records' USING ERRCODE = '23514';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION finance.require_open_period() FROM PUBLIC;

CREATE FUNCTION finance.protect_closing_snapshot() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $fn$
BEGIN
    IF TG_OP = 'DELETE' AND EXISTS (
        SELECT 1 FROM household.households
        WHERE id = OLD.household_id AND deleted_at IS NOT NULL
          AND recoverable_until <= statement_timestamp()
        FOR SHARE
    ) THEN
        -- Only the operational purge may receive DELETE privileges on these tables.
        RETURN OLD;
    END IF;
    RAISE EXCEPTION 'Closing snapshots are immutable; deletion requires an expired household recovery period'
        USING ERRCODE = '23514';
END;
$fn$;

REVOKE EXECUTE ON FUNCTION finance.protect_closing_snapshot() FROM PUBLIC;

CREATE FUNCTION finance.reset_category_payment() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $fn$
DECLARE category_id uuid; previous_category_id uuid; target_household uuid; target_period uuid;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF (NEW.amount, NEW.period_category_id) IS NOT DISTINCT FROM (OLD.amount, OLD.period_category_id) THEN RETURN NULL; END IF;
        previous_category_id := OLD.period_category_id;
    END IF;
    category_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.period_category_id ELSE NEW.period_category_id END;
    target_household := CASE WHEN TG_OP = 'DELETE' THEN OLD.household_id ELSE NEW.household_id END;
    target_period := CASE WHEN TG_OP = 'DELETE' THEN OLD.monthly_period_id ELSE NEW.monthly_period_id END;
    -- During an authorized purge no payment state needs to be rewritten.
    IF EXISTS (SELECT 1 FROM household.households WHERE id = target_household AND deleted_at IS NOT NULL) THEN RETURN NULL; END IF;
    UPDATE finance.period_categories
    SET payment_status = 'pending', paid_at = NULL, paid_by_user_id = NULL
    WHERE household_id = target_household AND monthly_period_id = target_period
      AND id IN (category_id, previous_category_id) AND payment_status = 'paid';
    RETURN NULL;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION finance.reset_category_payment() FROM PUBLIC;

CREATE TRIGGER tr_touch_updated_at BEFORE UPDATE ON identity.users FOR EACH ROW EXECUTE FUNCTION identity.touch_updated_at();

CREATE TRIGGER tr_touch_updated_at BEFORE UPDATE ON identity.login_blocks FOR EACH ROW EXECUTE FUNCTION identity.touch_updated_at();

CREATE TRIGGER tr_touch_updated_at BEFORE UPDATE ON identity.identity_reconciliations FOR EACH ROW EXECUTE FUNCTION identity.touch_updated_at();

CREATE TRIGGER tr_touch_updated_at BEFORE UPDATE ON household.households FOR EACH ROW EXECUTE FUNCTION identity.touch_updated_at();

CREATE TRIGGER tr_touch_updated_at BEFORE UPDATE ON household.household_members FOR EACH ROW EXECUTE FUNCTION identity.touch_updated_at();

CREATE TRIGGER tr_touch_updated_at BEFORE UPDATE ON household.household_invitations FOR EACH ROW EXECUTE FUNCTION identity.touch_updated_at();

CREATE TRIGGER tr_touch_updated_at BEFORE UPDATE ON finance.monthly_periods FOR EACH ROW EXECUTE FUNCTION identity.touch_updated_at();

CREATE TRIGGER tr_touch_updated_at BEFORE UPDATE ON finance.expense_categories FOR EACH ROW EXECUTE FUNCTION identity.touch_updated_at();

CREATE TRIGGER tr_touch_updated_at BEFORE UPDATE ON finance.period_categories FOR EACH ROW EXECUTE FUNCTION identity.touch_updated_at();

CREATE TRIGGER tr_require_open_period BEFORE INSERT OR UPDATE OR DELETE ON finance.period_categories FOR EACH ROW EXECUTE FUNCTION finance.require_open_period();

CREATE TRIGGER tr_touch_updated_at BEFORE UPDATE ON finance.expense_entries FOR EACH ROW EXECUTE FUNCTION identity.touch_updated_at();

CREATE TRIGGER tr_require_open_period BEFORE INSERT OR UPDATE OR DELETE ON finance.expense_entries FOR EACH ROW EXECUTE FUNCTION finance.require_open_period();

CREATE TRIGGER tr_touch_updated_at BEFORE UPDATE ON finance.period_participants FOR EACH ROW EXECUTE FUNCTION identity.touch_updated_at();

CREATE TRIGGER tr_require_open_period BEFORE INSERT OR UPDATE OR DELETE ON finance.period_participants FOR EACH ROW EXECUTE FUNCTION finance.require_open_period();

CREATE TRIGGER tr_touch_updated_at BEFORE UPDATE ON finance.salary_entries FOR EACH ROW EXECUTE FUNCTION identity.touch_updated_at();

CREATE TRIGGER tr_require_open_period BEFORE INSERT OR UPDATE OR DELETE ON finance.salary_entries FOR EACH ROW EXECUTE FUNCTION finance.require_open_period();

CREATE TRIGGER tr_touch_updated_at BEFORE UPDATE ON finance.benefits FOR EACH ROW EXECUTE FUNCTION identity.touch_updated_at();

CREATE TRIGGER tr_touch_updated_at BEFORE UPDATE ON finance.benefit_priorities FOR EACH ROW EXECUTE FUNCTION identity.touch_updated_at();

CREATE TRIGGER tr_touch_updated_at BEFORE UPDATE ON finance.benefit_entries FOR EACH ROW EXECUTE FUNCTION identity.touch_updated_at();

CREATE TRIGGER tr_require_open_period BEFORE INSERT OR UPDATE OR DELETE ON finance.benefit_entries FOR EACH ROW EXECUTE FUNCTION finance.require_open_period();

CREATE TRIGGER tr_touch_updated_at BEFORE UPDATE ON finance.period_benefit_priorities FOR EACH ROW EXECUTE FUNCTION identity.touch_updated_at();

CREATE TRIGGER tr_require_open_period BEFORE INSERT OR UPDATE OR DELETE ON finance.period_benefit_priorities FOR EACH ROW EXECUTE FUNCTION finance.require_open_period();

CREATE TRIGGER tr_touch_updated_at BEFORE UPDATE ON income.income_sources FOR EACH ROW EXECUTE FUNCTION identity.touch_updated_at();

CREATE TRIGGER tr_touch_updated_at BEFORE UPDATE ON income.income_entries FOR EACH ROW EXECUTE FUNCTION identity.touch_updated_at();

CREATE TRIGGER tr_require_open_period BEFORE INSERT OR UPDATE OR DELETE ON income.income_entries FOR EACH ROW EXECUTE FUNCTION finance.require_open_period();

CREATE TRIGGER tr_reject_history_update BEFORE UPDATE ON finance.migration_records FOR EACH ROW EXECUTE FUNCTION identity.reject_history_update();

CREATE TRIGGER tr_reject_history_update BEFORE UPDATE ON finance.migration_items FOR EACH ROW EXECUTE FUNCTION identity.reject_history_update();

CREATE TRIGGER tr_reject_history_update BEFORE UPDATE ON finance.export_records FOR EACH ROW EXECUTE FUNCTION identity.reject_history_update();

CREATE TRIGGER tr_reject_history_update BEFORE UPDATE ON finance.entry_revisions FOR EACH ROW EXECUTE FUNCTION identity.reject_history_update();

CREATE TRIGGER tr_touch_updated_at BEFORE UPDATE ON identity.idempotency_records FOR EACH ROW EXECUTE FUNCTION identity.touch_updated_at();

CREATE TRIGGER tr_reject_history_update BEFORE UPDATE ON identity.audit_logs FOR EACH ROW EXECUTE FUNCTION identity.reject_history_update();

CREATE TRIGGER tr_touch_updated_at BEFORE UPDATE ON household.idempotency_records FOR EACH ROW EXECUTE FUNCTION identity.touch_updated_at();

CREATE TRIGGER tr_reject_history_update BEFORE UPDATE ON household.audit_logs FOR EACH ROW EXECUTE FUNCTION identity.reject_history_update();

CREATE TRIGGER tr_touch_updated_at BEFORE UPDATE ON finance.idempotency_records FOR EACH ROW EXECUTE FUNCTION identity.touch_updated_at();

CREATE TRIGGER tr_reject_history_update BEFORE UPDATE ON finance.audit_logs FOR EACH ROW EXECUTE FUNCTION identity.reject_history_update();

CREATE TRIGGER tr_touch_updated_at BEFORE UPDATE ON income.idempotency_records FOR EACH ROW EXECUTE FUNCTION identity.touch_updated_at();

CREATE TRIGGER tr_reject_history_update BEFORE UPDATE ON income.audit_logs FOR EACH ROW EXECUTE FUNCTION identity.reject_history_update();

CREATE TRIGGER tr_serialize_membership BEFORE INSERT OR UPDATE OR DELETE ON household.household_members FOR EACH ROW EXECUTE FUNCTION household.serialize_membership();

CREATE TRIGGER tr_protect_period_identity BEFORE UPDATE ON finance.monthly_periods FOR EACH ROW EXECUTE FUNCTION finance.protect_period_identity();

CREATE CONSTRAINT TRIGGER ct_require_active_admin AFTER INSERT OR UPDATE OR DELETE ON household.households DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION household.require_active_admin();

CREATE CONSTRAINT TRIGGER ct_require_active_admin AFTER INSERT OR UPDATE OR DELETE ON household.household_members DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION household.require_active_admin();

CREATE TRIGGER tr_protect_snapshot BEFORE UPDATE OR DELETE ON finance.monthly_period_versions FOR EACH ROW EXECUTE FUNCTION finance.protect_closing_snapshot();

CREATE TRIGGER tr_protect_snapshot BEFORE UPDATE OR DELETE ON finance.allocation_snapshots FOR EACH ROW EXECUTE FUNCTION finance.protect_closing_snapshot();

CREATE TRIGGER tr_require_open_period BEFORE INSERT ON finance.monthly_period_versions FOR EACH ROW EXECUTE FUNCTION finance.require_open_period();

CREATE TRIGGER tr_reset_category_payment AFTER INSERT OR DELETE OR UPDATE OF amount, period_category_id ON finance.expense_entries FOR EACH ROW EXECUTE FUNCTION finance.reset_category_payment();
