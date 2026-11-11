-- HU-COM-008 (-db) docs issue #174, plan D-03 and DP-D8-1 (PROPOSED default, debt DD-1): one account is one customer record inside a tenant
-- (ADR-004 D5). Partial, so the many customers registered by an internal user, with no account, stay free. Built CONCURRENTLY, as the only
-- statement of its changeset and outside a transaction, so writes to customer are not blocked (norm 5.2.7). If a failed build left an invalid
-- index, drop it before the retry. The duplicate check (empty today) is: select tenant_id, account_id from customer where account_id is not null group by 1, 2 having count(*) > 1.
CREATE UNIQUE INDEX CONCURRENTLY uq_customer_tenant_id_account_id ON commercial_reservation.customer (tenant_id, account_id) WHERE account_id IS NOT NULL;
