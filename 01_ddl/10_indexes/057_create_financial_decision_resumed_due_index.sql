-- HU-COM-020 (-db) AC-20.5: the due read of job 2 for the decisions that resumed, an open and unfrozen decision by its shifted due instant, led by the tenant. Partial, so the hot rows stay small. Built
-- CONCURRENTLY, as the only statement of its changeset and outside a transaction (norm 5.2.7). If a failed build left an invalid index, drop it before the retry.
CREATE INDEX CONCURRENTLY idx_financial_decision_tenant_resumed_due ON commercial_reservation.financial_decision (tenant_id, resumed_due_at) WHERE outcome IS NULL AND frozen_at IS NULL AND resumed_due_at IS NOT NULL;
