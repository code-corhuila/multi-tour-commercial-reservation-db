-- HU-COM-020 AC-20.13 (-db): drops the reason column. A database that already holds a marked event refuses this revert on purpose: the audit marks are never erased by a migration; the owner decides.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM commercial_reservation.outbox_event WHERE reason IS NOT NULL) THEN
        RAISE EXCEPTION 'outbox_event holds events marked with a reason: the revert would erase the audit marks'
            USING ERRCODE = 'check_violation';
    END IF;
END
$$;
ALTER TABLE commercial_reservation.outbox_event
    DROP CONSTRAINT chk_outbox_event_reason,
    DROP COLUMN reason;
