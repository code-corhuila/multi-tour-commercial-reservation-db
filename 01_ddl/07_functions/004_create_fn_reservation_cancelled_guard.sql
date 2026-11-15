-- HU-COM-011 (-db) plan D-04, AC-D11.8 (RF-021, PROPOSED): Cancelada is terminal. A row whose stored status is CANCELLED is never updated again, so it is never
-- reactivated and its seat and value columns are protected too. The update that cancels has an OLD status that is not CANCELLED, so it passes. The message starts
-- with the constant trg_reservation_cancelled_guard so it can be searched.
CREATE FUNCTION commercial_reservation.fn_reservation_cancelled_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.reservation_status = 'CANCELLED' THEN
        RAISE EXCEPTION 'trg_reservation_cancelled_guard: a cancelled reservation is terminal and is never updated'
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
