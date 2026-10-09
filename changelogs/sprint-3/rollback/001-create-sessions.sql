DROP TABLE identity.sessions;
DROP TABLE identity.login_guards;
-- Existing email-only audit history must survive rollback; ip_hash remains nullable.
-- Restoring NOT NULL would require deleting history or fabricating IP evidence.
