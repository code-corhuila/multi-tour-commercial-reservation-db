-- HU-COM-018 (-db) plan D-07, AC-D18.14: the episodes of a tenant that wait for a proposal and are not frozen, read by the due list of job 5.
CREATE INDEX idx_rescheduling_episode_tenant_due ON commercial_reservation.rescheduling_episode (tenant_id, proposal_due_at) WHERE episode_state = 'OPEN' AND frozen_at IS NULL;
