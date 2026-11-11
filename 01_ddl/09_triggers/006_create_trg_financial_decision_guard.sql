-- HU-COM-016 (-db) plan D-04: fires on UPDATE only, so the recording of a decision is free.
CREATE TRIGGER trg_financial_decision_guard BEFORE UPDATE ON commercial_reservation.financial_decision
    FOR EACH ROW EXECUTE FUNCTION commercial_reservation.fn_financial_decision_guard();
