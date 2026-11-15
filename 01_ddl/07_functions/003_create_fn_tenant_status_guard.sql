-- HU-WRK-007 -db spec 021 D-03 (PROPOSED): the identifier of a tenant never changes (ADR-004 D5), because every shared link
-- depends on it. The engine refuses the change, not only the application.
CREATE FUNCTION commercial_reservation.fn_tenant_status_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.identifier IS DISTINCT FROM OLD.identifier THEN
        RAISE EXCEPTION 'tenant_status identifier cannot change (tenant %)', OLD.tenant_id
            USING ERRCODE = 'integrity_constraint_violation';
    END IF;
    RETURN NEW;
END;
$$;
