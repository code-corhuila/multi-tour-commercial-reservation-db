-- HU-COM-010 (-db) plan D-04: fires on UPDATE only, so the registration of an attempt (INSERT) is free.
CREATE TRIGGER trg_payment_attempt_guard BEFORE UPDATE ON commercial_reservation.payment_attempt
    FOR EACH ROW EXECUTE FUNCTION commercial_reservation.fn_payment_attempt_guard();
