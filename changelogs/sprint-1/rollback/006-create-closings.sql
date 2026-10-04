-- PostgreSQL 17+ | Sprint 1 | 006-create-closings

ALTER TABLE finance.monthly_periods DROP CONSTRAINT fk_period_latest_closed_version;

DROP INDEX finance.ix_periods_latest_closed_version;

ALTER TABLE finance.monthly_period_versions DROP CONSTRAINT fk_period_version_required_allocation;

DROP TABLE finance.allocation_snapshots;

DROP TABLE finance.monthly_period_versions;
