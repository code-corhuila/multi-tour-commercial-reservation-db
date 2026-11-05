-- HU-COM-016 (-db) plan D-05, AC-D16.13: the due list of job 2 is a range read of the open, unfrozen decisions of a tenant by recognition instant.
CREATE INDEX idx_financial_decision_tenant_due ON commercial_reservation.financial_decision (tenant_id, recognized_at) WHERE outcome IS NULL AND frozen_at IS NULL;
