-- HU-COM-020 (-db) plan D-04 (PROPOSED default, DP-D20-3): a freeze has a cause. A deadline frozen by the inactivation of the tenant is resumed by its reactivation; one frozen by the cancellation or
-- interruption of its departure is not. The column is nullable and present exactly when frozen_at is, so every row that existed stays valid (none is frozen). No DEFAULT.
ALTER TABLE commercial_reservation.payment_deadline
    ADD COLUMN freeze_cause text,
    ADD CONSTRAINT chk_payment_deadline_freeze_cause CHECK (freeze_cause IS NULL OR freeze_cause IN ('TENANT_INACTIVE', 'DEPARTURE_CANCELLED_OR_INTERRUPTED')),
    ADD CONSTRAINT chk_payment_deadline_freeze_cause_complete CHECK ((freeze_cause IS NULL) = (frozen_at IS NULL));
