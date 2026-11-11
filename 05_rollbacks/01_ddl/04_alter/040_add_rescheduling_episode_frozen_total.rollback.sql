ALTER TABLE commercial_reservation.rescheduling_episode
    DROP CONSTRAINT chk_rescheduling_episode_frozen_total,
    DROP COLUMN frozen_total_minutes;
