-- HU-COM-017 (-db) plan D-04: fires on every insert of an application, row level, so a direct insert cannot spend another customer's credit.
CREATE TRIGGER trg_credit_balance_application_guard BEFORE INSERT ON commercial_reservation.credit_balance_application
    FOR EACH ROW EXECUTE FUNCTION commercial_reservation.fn_credit_balance_application_guard();
