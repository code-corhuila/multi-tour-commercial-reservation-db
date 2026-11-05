-- HU-COM-015 (-db) plan D-04: fires on UPDATE and DELETE of each row, so the insert of an event is free.
CREATE TRIGGER trg_outbox_event_delivery_guard BEFORE UPDATE OR DELETE ON commercial_reservation.outbox_event
    FOR EACH ROW EXECUTE FUNCTION commercial_reservation.fn_outbox_event_delivery_guard();
