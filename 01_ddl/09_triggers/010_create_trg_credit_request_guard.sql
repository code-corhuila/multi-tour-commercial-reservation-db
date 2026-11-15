-- HU-COM-017 (-db) plan D-05: fires only on the insert of a credit-balance refund request, so the decisions of the other kinds pay nothing for it.
CREATE TRIGGER trg_credit_request_guard BEFORE INSERT ON commercial_reservation.financial_decision
    FOR EACH ROW WHEN (NEW.decision_kind = 'CREDIT_BALANCE_REFUND_REQUEST') EXECUTE FUNCTION commercial_reservation.fn_credit_request_guard();
