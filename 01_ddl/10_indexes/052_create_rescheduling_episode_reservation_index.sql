-- HU-COM-018 (-db) plan D-07, AC-D18.14: the episodes of one reservation, led by the tenant.
CREATE INDEX idx_rescheduling_episode_tenant_reservation ON commercial_reservation.rescheduling_episode (tenant_id, reservation_id);
