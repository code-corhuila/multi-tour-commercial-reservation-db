-- HU-COM-020 (-db) plan D-03: fires on every update of a suspension, row level, so a direct update cannot rewrite the history.
CREATE TRIGGER trg_tenant_suspension_guard BEFORE UPDATE ON commercial_reservation.tenant_suspension
    FOR EACH ROW EXECUTE FUNCTION commercial_reservation.fn_tenant_suspension_guard();
