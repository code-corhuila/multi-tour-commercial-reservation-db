-- HU-COM-016 (-db) plan D-04: fires on UPDATE only, so the authorization of a refund is free.
CREATE TRIGGER trg_refund_authorization_guard BEFORE UPDATE ON commercial_reservation.refund_authorization
    FOR EACH ROW EXECUTE FUNCTION commercial_reservation.fn_refund_authorization_guard();
