-- HU-COM-017 (-db) plan D-04, AC-D17.7, AC-D17.8: an application of a credit never crosses a tenant or a customer and never passes the recorded amount. The credit is
-- locked first with a transaction advisory lock keyed by its id (the writer holds no UPDATE on the table, so a row lock is not available to it), so two concurrent inserts wait
-- for each other and the second sees the first. The target reservation must be of the credit's tenant and of the
-- customer of the credit's source reservation. The sum of the applications, plus the live refund requests of that credit (an open or authorized decision of kind
-- CREDIT_BALANCE_REFUND_REQUEST), plus the new amount, may not exceed the recorded amount. Reads only the tables named. Rejects with the constant
-- trg_credit_balance_application_guard.
CREATE FUNCTION commercial_reservation.fn_credit_balance_application_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    credit_tenant uuid;
    credit_amount bigint;
    source_customer uuid;
    target_tenant uuid;
    target_customer uuid;
    used bigint;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended(NEW.credit_balance_id::text, 0));
    SELECT c.tenant_id, c.amount_cents, r.customer_id INTO credit_tenant, credit_amount, source_customer
      FROM commercial_reservation.credit_balance c
      JOIN commercial_reservation.reservation r ON r.reservation_id = c.source_reservation_id
     WHERE c.credit_balance_id = NEW.credit_balance_id;
    SELECT tenant_id, customer_id INTO target_tenant, target_customer
      FROM commercial_reservation.reservation WHERE reservation_id = NEW.target_reservation_id;
    IF credit_tenant IS DISTINCT FROM NEW.tenant_id OR target_tenant IS DISTINCT FROM credit_tenant THEN
        RAISE EXCEPTION 'trg_credit_balance_application_guard: a credit balance is applied only inside the tenant that recorded it'
            USING ERRCODE = 'check_violation';
    END IF;
    IF target_customer IS DISTINCT FROM source_customer THEN
        RAISE EXCEPTION 'trg_credit_balance_application_guard: a credit balance is applied only to a reservation of its own customer'
            USING ERRCODE = 'check_violation';
    END IF;
    SELECT COALESCE((SELECT sum(applied_amount_cents) FROM commercial_reservation.credit_balance_application WHERE credit_balance_id = NEW.credit_balance_id), 0)
         + COALESCE((SELECT sum(base_amount_cents) FROM commercial_reservation.financial_decision
                      WHERE credit_balance_id = NEW.credit_balance_id AND decision_kind = 'CREDIT_BALANCE_REFUND_REQUEST'
                        AND (outcome IS NULL OR outcome = 'AUTHORIZED')), 0)
      INTO used;
    IF used + NEW.applied_amount_cents > credit_amount THEN
        RAISE EXCEPTION 'trg_credit_balance_application_guard: the applied and set-aside value cannot exceed the recorded amount'
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
