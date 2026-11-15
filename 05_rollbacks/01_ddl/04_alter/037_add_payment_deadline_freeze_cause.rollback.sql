ALTER TABLE commercial_reservation.payment_deadline
    DROP CONSTRAINT chk_payment_deadline_freeze_cause_complete,
    DROP CONSTRAINT chk_payment_deadline_freeze_cause,
    DROP COLUMN freeze_cause;
