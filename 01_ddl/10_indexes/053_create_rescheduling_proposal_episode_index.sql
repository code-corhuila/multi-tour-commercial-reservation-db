-- HU-COM-018 (-db) plan D-07, AC-D18.14: the proposals of one episode, led by the tenant.
CREATE INDEX idx_rescheduling_proposal_tenant_episode ON commercial_reservation.rescheduling_proposal (tenant_id, rescheduling_episode_id);
