-- HU-COM-020 (-db) AC-18.13, AC-20.6 (PROPOSED default): the clock of a rescheduling episode freezes with its tenant and resumes with the time it had left. episode_started_at is immutable (the guard of
-- 011), so the minutes the episode spent frozen are kept here, summed over every freeze it has had: the limit of 96 hours moves by that total. Nullable (empty until the first resume), no DEFAULT, never negative.
ALTER TABLE commercial_reservation.rescheduling_episode
    ADD COLUMN frozen_total_minutes integer,
    ADD CONSTRAINT chk_rescheduling_episode_frozen_total CHECK (frozen_total_minutes IS NULL OR frozen_total_minutes >= 0);
