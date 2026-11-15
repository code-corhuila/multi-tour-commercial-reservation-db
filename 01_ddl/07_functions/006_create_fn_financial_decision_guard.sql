-- HU-COM-016 (-db) plan D-04, AC-D16.6 (RN-RES-006C, GAP-003): a decision is recorded once. A decided row changes nothing; an open row may change only its base
-- amount, its penalty (a late value recognized for an open decision), its freeze pair and the outcome group that decides it. Reads no other table.
-- Rejects with the constant trg_financial_decision_guard.
CREATE FUNCTION commercial_reservation.fn_financial_decision_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.outcome IS NOT NULL THEN
        RAISE EXCEPTION 'trg_financial_decision_guard: a decided financial decision cannot change'
            USING ERRCODE = 'check_violation';
    END IF;
    IF (NEW.financial_decision_id, NEW.tenant_id, NEW.reservation_id, NEW.credit_balance_id, NEW.decision_kind, NEW.recognized_at)
       IS DISTINCT FROM (OLD.financial_decision_id, OLD.tenant_id, OLD.reservation_id, OLD.credit_balance_id, OLD.decision_kind, OLD.recognized_at) THEN
        RAISE EXCEPTION 'trg_financial_decision_guard: an open financial decision may change only its amounts, its freeze and its outcome'
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
