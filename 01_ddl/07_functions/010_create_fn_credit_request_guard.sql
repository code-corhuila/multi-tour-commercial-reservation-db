-- HU-COM-017 (-db) plan D-05, AC-D17.8: a refund request of a credit (a decision of kind CREDIT_BALANCE_REFUND_REQUEST) may not set aside more than the credit holds. The credit
-- row is locked FOR UPDATE first, as in 009, so a request and an application at once cannot both pass. The applications plus the live requests (open or authorized) plus
-- the new base amount may not exceed the recorded amount. The other decision kinds are not touched. Rejects with the constant trg_credit_request_guard.
CREATE FUNCTION commercial_reservation.fn_credit_request_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    credit_amount bigint;
    used bigint;
BEGIN
    SELECT amount_cents INTO credit_amount
      FROM commercial_reservation.credit_balance WHERE credit_balance_id = NEW.credit_balance_id FOR UPDATE;
    SELECT COALESCE((SELECT sum(applied_amount_cents) FROM commercial_reservation.credit_balance_application WHERE credit_balance_id = NEW.credit_balance_id), 0)
         + COALESCE((SELECT sum(base_amount_cents) FROM commercial_reservation.financial_decision
                      WHERE credit_balance_id = NEW.credit_balance_id AND decision_kind = 'CREDIT_BALANCE_REFUND_REQUEST'
                        AND (outcome IS NULL OR outcome = 'AUTHORIZED')), 0)
      INTO used;
    IF credit_amount IS NULL OR used + NEW.base_amount_cents > credit_amount THEN
        RAISE EXCEPTION 'trg_credit_request_guard: the applied and set-aside value cannot exceed the recorded amount'
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
