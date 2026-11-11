-- HU-COM-011 (-db) plan D-04: fires on UPDATE only, row level, so the birth of a reservation (INSERT, trg_reservation_birth) is untouched.
CREATE TRIGGER trg_reservation_cancelled_guard BEFORE UPDATE ON commercial_reservation.reservation
    FOR EACH ROW EXECUTE FUNCTION commercial_reservation.fn_reservation_cancelled_guard();
