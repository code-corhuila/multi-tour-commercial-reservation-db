-- HU-COM-018 (-db) plan D-02, AC-D18.5 (FINAL-011): one open episode per reservation, led by the tenant.
CREATE UNIQUE INDEX uq_rescheduling_episode_open_reservation ON commercial_reservation.rescheduling_episode (tenant_id, reservation_id) WHERE episode_state = 'OPEN';
