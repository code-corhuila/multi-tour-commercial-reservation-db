-- HU-COM-007 (-db) plan D-05 (PROPOSED): the birth rule of a reservation (RN-RES-006, AC-D7.4). A CHECK cannot tell an insert from a
-- later update (CONFIRMED is legitimate later), so the rule is a BEFORE INSERT function. It reads no other table.
-- BEFORE triggers run before the NOT NULL constraints, so a null is left to its named constraint: each comparison is skipped when a side is null.
-- final_value_cents <= projected_value_cents holds only at birth, because the discounts only subtract (PROPUESTO, RN-RES-002).
CREATE FUNCTION commercial_reservation.trg_reservation_birth() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.reservation_status <> 'PENDING_PAYMENT' THEN
        RAISE EXCEPTION 'trg_reservation_birth: a reservation is born PENDING_PAYMENT, not %', NEW.reservation_status
            USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.payment_status <> 'NO_PAYMENT' THEN
        RAISE EXCEPTION 'trg_reservation_birth: a reservation is born NO_PAYMENT, not %', NEW.payment_status
            USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.pending_balance_cents <> NEW.final_value_cents THEN
        RAISE EXCEPTION 'trg_reservation_birth: the pending balance must equal the final value at birth'
            USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.final_value_cents > NEW.projected_value_cents THEN
        RAISE EXCEPTION 'trg_reservation_birth: the final value cannot be above the projected value at birth'
            USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.credit_balance_cents <> 0 THEN
        RAISE EXCEPTION 'trg_reservation_birth: the credit balance must be zero at birth'
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
