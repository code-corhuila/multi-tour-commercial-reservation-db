-- HU-COM-018 (-db) plan D-03, AC-D18.8 (RN-EJE-002): one pending proposal per episode, led by the tenant.
CREATE UNIQUE INDEX uq_rescheduling_proposal_pending_episode ON commercial_reservation.rescheduling_proposal (tenant_id, rescheduling_episode_id) WHERE proposal_state = 'PENDING';
