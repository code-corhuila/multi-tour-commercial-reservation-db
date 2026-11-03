-- HU-COM-011 (-db) plan D-03: fires on UPDATE only, so the creation of a deadline is free.
CREATE TRIGGER trg_payment_deadline_extension_guard BEFORE UPDATE ON commercial_reservation.payment_deadline
    FOR EACH ROW EXECUTE FUNCTION commercial_reservation.fn_payment_deadline_extension_guard();
