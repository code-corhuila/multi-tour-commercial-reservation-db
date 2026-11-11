-- HU-COM-016 (-db) plan D-04, AC-D16.11 (RF-015B, RN-RES-008 L3): a refund goes forward only. The state may move AUTHORIZED -> EXECUTING, EXECUTING -> AUTHORIZED
-- (the undo of the saga) and EXECUTING -> EXECUTED; an EXECUTED row changes nothing; every column of the authorization is immutable; the overdue mark is set once
-- and never on an executed refund. Reads no other table. Rejects with the constant trg_refund_authorization_guard.
CREATE FUNCTION commercial_reservation.fn_refund_authorization_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.execution_state = 'EXECUTED' THEN
        RAISE EXCEPTION 'trg_refund_authorization_guard: an executed refund cannot change'
            USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.execution_state <> OLD.execution_state
       AND (OLD.execution_state, NEW.execution_state) NOT IN (('AUTHORIZED', 'EXECUTING'), ('EXECUTING', 'AUTHORIZED'), ('EXECUTING', 'EXECUTED')) THEN
        RAISE EXCEPTION 'trg_refund_authorization_guard: the state of a refund cannot move from % to %', OLD.execution_state, NEW.execution_state
            USING ERRCODE = 'check_violation';
    END IF;
    IF (NEW.refund_authorization_id, NEW.tenant_id, NEW.reservation_id, NEW.refund_origin, NEW.financial_decision_id, NEW.potential_refund_value_cents,
        NEW.authorized_amount_cents, NEW.reason, NEW.authorization_mode, NEW.authorized_by, NEW.authorized_at, NEW.execution_due_at)
       IS DISTINCT FROM (OLD.refund_authorization_id, OLD.tenant_id, OLD.reservation_id, OLD.refund_origin, OLD.financial_decision_id, OLD.potential_refund_value_cents,
        OLD.authorized_amount_cents, OLD.reason, OLD.authorization_mode, OLD.authorized_by, OLD.authorized_at, OLD.execution_due_at) THEN
        RAISE EXCEPTION 'trg_refund_authorization_guard: the authorization of a refund cannot change'
            USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.overdue_marked_at IS DISTINCT FROM OLD.overdue_marked_at
       AND (OLD.overdue_marked_at IS NOT NULL OR NEW.overdue_marked_at IS NULL OR NEW.execution_state = 'EXECUTED') THEN
        RAISE EXCEPTION 'trg_refund_authorization_guard: the overdue mark is set once and never on an executed refund'
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
