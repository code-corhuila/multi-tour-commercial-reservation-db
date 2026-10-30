-- HU-COM-008 (-db) plan D-03: the partial non-unique index of HU-COM-005 (10_indexes/009) is redundant once the unique one above is valid.
-- Its own changeset, one statement, outside a transaction. The rollback recreates it exactly as 009 left it.
DROP INDEX CONCURRENTLY commercial_reservation.idx_customer_tenant_account_id;
