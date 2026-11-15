-- HU-COM-020 (-db) plan D-03, AC-D20.4: a suspension is closed once and never rewritten. The guard raises unless the old row is open and the only columns that change are resumed_at and
-- resumed_by_event_id, both set; a closed row never changes. A delete is already refused by the missing grant. Reads no other table. Rejects with the constant trg_tenant_suspension_guard.
CREATE FUNCTION commercial_reservation.fn_tenant_suspension_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.resumed_at IS NOT NULL THEN
        RAISE EXCEPTION 'trg_tenant_suspension_guard: a closed suspension never changes' USING ERRCODE = 'check_violation';
    END IF;
    IF (NEW.tenant_suspension_id, NEW.tenant_id, NEW.suspended_at, NEW.suspended_by_event_id)
       IS DISTINCT FROM (OLD.tenant_suspension_id, OLD.tenant_id, OLD.suspended_at, OLD.suspended_by_event_id)
       OR NEW.resumed_at IS NULL OR NEW.resumed_by_event_id IS NULL THEN
        RAISE EXCEPTION 'trg_tenant_suspension_guard: an open suspension is only closed, with its instant and its event' USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
