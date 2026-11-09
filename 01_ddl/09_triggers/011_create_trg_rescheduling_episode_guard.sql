-- HU-COM-018 (-db) plan D-05: fires on every update of an episode, row level, so a direct update cannot reopen or rewrite a closed one.
CREATE TRIGGER trg_rescheduling_episode_guard BEFORE UPDATE ON commercial_reservation.rescheduling_episode
    FOR EACH ROW EXECUTE FUNCTION commercial_reservation.fn_rescheduling_episode_guard();
