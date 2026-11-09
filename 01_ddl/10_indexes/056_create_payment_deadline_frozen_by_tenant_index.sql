-- HU-COM-020 (-db) plan D-05, AC-D20.10: the resume scan reads only the deadlines of a tenant frozen by its inactivation. Partial, so the hot rows stay small. Built CONCURRENTLY, as the only statement of its
-- changeset and outside a transaction, so the writes of the table are not blocked (norm 5.2.7). If a failed build left an invalid index, drop it before the retry.
CREATE INDEX CONCURRENTLY idx_payment_deadline_tenant_frozen_by_tenant ON commercial_reservation.payment_deadline (tenant_id) WHERE freeze_cause = 'TENANT_INACTIVE';
