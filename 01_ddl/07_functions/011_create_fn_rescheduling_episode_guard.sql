-- HU-COM-018 (-db) plan D-05, AC-D18.9: an episode moves forward only. A closed episode never changes; an open one either keeps its state (and may then change only the freeze pair and
-- the due instant of the proposal, which a resume moves) or closes into RESCHEDULED or CANCELLED (and may then change only the state group: state, closing instant and reason).
-- Reads no other table. Rejects with the constant trg_rescheduling_episode_guard.
CREATE FUNCTION commercial_reservation.fn_rescheduling_episode_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.episode_state <> 'OPEN' THEN
        RAISE EXCEPTION 'trg_rescheduling_episode_guard: a closed episode never changes' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.episode_state NOT IN ('OPEN', 'RESCHEDULED', 'CANCELLED') THEN
        RAISE EXCEPTION 'trg_rescheduling_episode_guard: an episode moves only to RESCHEDULED or CANCELLED' USING ERRCODE = 'check_violation';
    END IF;
    IF (NEW.rescheduling_episode_id, NEW.tenant_id, NEW.reservation_id, NEW.original_salida_id, NEW.episode_started_at, NEW.opened_at)
       IS DISTINCT FROM (OLD.rescheduling_episode_id, OLD.tenant_id, OLD.reservation_id, OLD.original_salida_id, OLD.episode_started_at, OLD.opened_at) THEN
        RAISE EXCEPTION 'trg_rescheduling_episode_guard: the identity of an episode never changes' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.episode_state = 'OPEN' AND (NEW.closed_at IS DISTINCT FROM OLD.closed_at OR NEW.closed_reason IS DISTINCT FROM OLD.closed_reason) THEN
        RAISE EXCEPTION 'trg_rescheduling_episode_guard: the closing columns are written together with the state' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.episode_state <> 'OPEN' AND (NEW.proposal_due_at IS DISTINCT FROM OLD.proposal_due_at
       OR NEW.frozen_at IS DISTINCT FROM OLD.frozen_at OR NEW.remaining_episode_minutes IS DISTINCT FROM OLD.remaining_episode_minutes) THEN
        RAISE EXCEPTION 'trg_rescheduling_episode_guard: closing an episode does not change its clocks' USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
