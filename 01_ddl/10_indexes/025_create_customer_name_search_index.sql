-- HU-COM-005 (-db) T-10, plan D-12 (PROPUESTO): the search of customers by name inside a tenant (AC-D5.11). The prefix is compared on lower(full_name),
-- so text_pattern_ops lets the planner use the index for LIKE 'ana%' whatever the collation. Only this search is built: the document and the e-mail
-- searches wait for DP-D5-2 and DP-D5-3. Built CONCURRENTLY, as the only statement of its changeset and outside a transaction, so writes to customer
-- are not blocked (norm 5.2.7). If a failed build left an invalid index, drop it before the retry.
CREATE INDEX CONCURRENTLY idx_customer_tenant_full_name ON commercial_reservation.customer (tenant_id, lower(full_name) text_pattern_ops);
