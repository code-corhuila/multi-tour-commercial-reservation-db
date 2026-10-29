-- HU-COM-010 (-db) plan D-04, DP-D10-3 (PROPOSED default, debt DD-1): the last line that keeps a decided proof final (portal AC-PV.9, RN-RES-006D); the
-- application also uses a conditional update, so this is not the first line. It raises when: a registration column changes at any time (including
-- payment_status_snapshot, which is write-once, X-2); the old state is APPROVED or REJECTED and the state, the author, the time, the reason or an amount
-- changes; or a cash attempt (no state) is given one. IN_VALIDATION may become APPROVED or REJECTED, which the table checks make complete. An update
-- that changes none of these passes. Every message starts with the constant trg_payment_attempt_guard so it can be searched.
CREATE FUNCTION commercial_reservation.fn_payment_attempt_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF (NEW.payment_attempt_id, NEW.tenant_id, NEW.reservation_id, NEW.payment_method, NEW.received_amount_cents,
        NEW.payment_status_snapshot, NEW.registered_by, NEW.registered_at)
       IS DISTINCT FROM
       (OLD.payment_attempt_id, OLD.tenant_id, OLD.reservation_id, OLD.payment_method, OLD.received_amount_cents,
        OLD.payment_status_snapshot, OLD.registered_by, OLD.registered_at) THEN
        RAISE EXCEPTION 'trg_payment_attempt_guard: the registration columns of an attempt never change'
            USING ERRCODE = 'check_violation';
    END IF;
    IF OLD.validation_status IN ('APPROVED', 'REJECTED') THEN
        IF (NEW.validation_status, NEW.decided_by, NEW.decided_at, NEW.decision_reason, NEW.verified_amount_cents,
            NEW.applied_amount_cents, NEW.excess_amount_cents, NEW.treatment_amount_cents)
           IS DISTINCT FROM
           (OLD.validation_status, OLD.decided_by, OLD.decided_at, OLD.decision_reason, OLD.verified_amount_cents,
            OLD.applied_amount_cents, OLD.excess_amount_cents, OLD.treatment_amount_cents) THEN
            RAISE EXCEPTION 'trg_payment_attempt_guard: a decided proof is final (%)', OLD.validation_status
                USING ERRCODE = 'check_violation';
        END IF;
    ELSIF OLD.validation_status IS NULL AND NEW.validation_status IS NOT NULL THEN
        RAISE EXCEPTION 'trg_payment_attempt_guard: a cash attempt never has a validation status'
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
