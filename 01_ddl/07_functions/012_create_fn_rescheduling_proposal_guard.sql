-- HU-COM-018 (-db) plan D-05, AC-D18.9 (GAP-008): a proposal is answered once. A closed proposal never changes. A pending one either keeps its state (and may then change only the
-- remaining minutes and the response deadline, which a freeze and a resume move) or leaves it to ACCEPTED, REJECTED, VOID or EXPIRED, writing the answer columns and the closing instant
-- together with the state. Nothing else of a proposal changes. Reads no other table. Rejects with the constant trg_rescheduling_proposal_guard.
CREATE FUNCTION commercial_reservation.fn_rescheduling_proposal_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.proposal_state <> 'PENDING' THEN
        RAISE EXCEPTION 'trg_rescheduling_proposal_guard: a closed proposal never changes' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.proposal_state NOT IN ('PENDING', 'ACCEPTED', 'REJECTED', 'VOID', 'EXPIRED') THEN
        RAISE EXCEPTION 'trg_rescheduling_proposal_guard: a proposal moves only to ACCEPTED, REJECTED, VOID or EXPIRED' USING ERRCODE = 'check_violation';
    END IF;
    IF (NEW.rescheduling_proposal_id, NEW.tenant_id, NEW.rescheduling_episode_id, NEW.reservation_id, NEW.proposed_salida_id, NEW.party_size, NEW.proposed_by, NEW.proposed_at)
       IS DISTINCT FROM (OLD.rescheduling_proposal_id, OLD.tenant_id, OLD.rescheduling_episode_id, OLD.reservation_id, OLD.proposed_salida_id, OLD.party_size, OLD.proposed_by, OLD.proposed_at) THEN
        RAISE EXCEPTION 'trg_rescheduling_proposal_guard: what was proposed never changes' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.proposal_state = 'PENDING' AND (NEW.answer_source IS DISTINCT FROM OLD.answer_source OR NEW.answer_channel IS DISTINCT FROM OLD.answer_channel
       OR NEW.answer_evidence IS DISTINCT FROM OLD.answer_evidence OR NEW.answered_at IS DISTINCT FROM OLD.answered_at OR NEW.answer_recorded_by IS DISTINCT FROM OLD.answer_recorded_by
       OR NEW.answer_recorded_at IS DISTINCT FROM OLD.answer_recorded_at OR NEW.closed_at IS DISTINCT FROM OLD.closed_at) THEN
        RAISE EXCEPTION 'trg_rescheduling_proposal_guard: the answer columns are written together with the state' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.proposal_state <> 'PENDING' AND (NEW.remaining_response_minutes IS DISTINCT FROM OLD.remaining_response_minutes OR NEW.response_deadline_at IS DISTINCT FROM OLD.response_deadline_at) THEN
        RAISE EXCEPTION 'trg_rescheduling_proposal_guard: answering a proposal does not change its clock' USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
