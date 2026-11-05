-- HU-COM-015 (-db) plan D-04, AC-D15.8 and AC-D15.9 (DP-D15-3 and DP-D15-4, PROPOSED defaults): delivery may change only its own columns, and a pending or failed event is
-- never deleted by the application. UPDATE: everything except published_at, attempts, last_error, next_attempt_at and failed_at must stay as it was written (so a column
-- added later is frozen by default), and an event that is already published or failed accepts no change at all. DELETE: refused when the event is unpublished or failed,
-- so that a failure stays visible (RF-019); a published event may be purged as ADR-004 D10 point 6 allows. A superuser, the role of the migrations and of maintenance,
-- is not the application and keeps the right to clean a disposable instance. Rejects with the constant trg_outbox_event_delivery_guard.
CREATE FUNCTION commercial_reservation.fn_outbox_event_delivery_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    delivery text[] := ARRAY['published_at', 'attempts', 'last_error', 'next_attempt_at', 'failed_at'];
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF (OLD.published_at IS NULL OR OLD.failed_at IS NOT NULL)
           AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
            RAISE EXCEPTION 'trg_outbox_event_delivery_guard: an unpublished or failed event cannot be deleted'
                USING ERRCODE = 'check_violation';
        END IF;
        RETURN OLD;
    END IF;
    IF (to_jsonb(NEW) - delivery) IS DISTINCT FROM (to_jsonb(OLD) - delivery) THEN
        RAISE EXCEPTION 'trg_outbox_event_delivery_guard: only the delivery columns of an event may change'
            USING ERRCODE = 'check_violation';
    END IF;
    IF (OLD.published_at IS NOT NULL OR OLD.failed_at IS NOT NULL)
       AND (to_jsonb(NEW) IS DISTINCT FROM to_jsonb(OLD)) THEN
        RAISE EXCEPTION 'trg_outbox_event_delivery_guard: the delivery data of a published or failed event is final'
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
