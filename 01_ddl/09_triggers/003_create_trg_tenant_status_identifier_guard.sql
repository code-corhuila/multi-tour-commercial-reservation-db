-- HU-WRK-007 -db spec 021 D-03 (PROPOSED): attaches the identifier guard; an update that leaves the identifier equal passes.
CREATE TRIGGER trg_tenant_status_identifier_guard
    BEFORE UPDATE ON commercial_reservation.tenant_status
    FOR EACH ROW EXECUTE FUNCTION commercial_reservation.fn_tenant_status_guard();
