-- HU-COM-007 (-db) plan D-05: fires on INSERT only, so every later update (confirmation, payments, modifications) is free.
CREATE TRIGGER trg_reservation_birth BEFORE INSERT ON commercial_reservation.reservation
    FOR EACH ROW EXECUTE FUNCTION commercial_reservation.trg_reservation_birth();
