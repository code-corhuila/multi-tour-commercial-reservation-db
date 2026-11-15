-- HU-COM-011 (-db) plan D-03, DP-D11-3 (PROPOSED default): the single extension and the freeze of a deadline. All columns are nullable and have no DEFAULT.
-- The extension is whole or absent (duration, instant, grantor), between 1 and 720 hours (as additional_wait_hours of payment_condition) and only on the
-- initial payment kind. The freeze is a pair: the instant and the minutes that remained. Who freezes and when is HU-COM-018 and HU-COM-020.
ALTER TABLE commercial_reservation.payment_deadline
    ADD COLUMN extension_hours integer,
    ADD COLUMN extension_granted_at timestamptz,
    ADD COLUMN extension_granted_by uuid,
    ADD COLUMN frozen_at timestamptz,
    ADD COLUMN remaining_at_freeze_minutes integer,
    ADD CONSTRAINT chk_payment_deadline_extension_complete CHECK (
        num_nonnulls(extension_hours, extension_granted_at, extension_granted_by) IN (0, 3)),
    ADD CONSTRAINT chk_payment_deadline_extension_hours CHECK (extension_hours IS NULL OR extension_hours BETWEEN 1 AND 720),
    ADD CONSTRAINT chk_payment_deadline_extension_kind CHECK (extension_hours IS NULL OR deadline_kind = 'INITIAL_PAYMENT'),
    ADD CONSTRAINT chk_payment_deadline_freeze_complete CHECK (num_nonnulls(frozen_at, remaining_at_freeze_minutes) IN (0, 2)),
    ADD CONSTRAINT chk_payment_deadline_remaining CHECK (remaining_at_freeze_minutes IS NULL OR remaining_at_freeze_minutes >= 0);
