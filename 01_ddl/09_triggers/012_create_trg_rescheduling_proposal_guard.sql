-- HU-COM-018 (-db) plan D-05: fires on every update of a proposal, row level, so a direct update cannot answer a proposal twice.
CREATE TRIGGER trg_rescheduling_proposal_guard BEFORE UPDATE ON commercial_reservation.rescheduling_proposal
    FOR EACH ROW EXECUTE FUNCTION commercial_reservation.fn_rescheduling_proposal_guard();
