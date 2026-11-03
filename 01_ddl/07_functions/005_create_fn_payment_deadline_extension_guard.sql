-- HU-COM-011 (-db) plan D-03, AC-D11.5 (RN-RES-006, one extension only): the first extension is final. An update may write the extension columns only while the
-- stored duration is null; afterwards the three columns may not change or be cleared. An update that leaves them as they are passes. Rejects with the constant
-- trg_payment_deadline_extension_guard.
CREATE FUNCTION commercial_reservation.fn_payment_deadline_extension_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.extension_hours IS NOT NULL
       AND (NEW.extension_hours, NEW.extension_granted_at, NEW.extension_granted_by)
           IS DISTINCT FROM (OLD.extension_hours, OLD.extension_granted_at, OLD.extension_granted_by) THEN
        RAISE EXCEPTION 'trg_payment_deadline_extension_guard: the single extension of a deadline is final'
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
