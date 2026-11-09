-- HU-COM-018 (-db) plan D-07, AC-D18.14: the pending proposals of a tenant by response deadline, read by the due list of job 5.
CREATE INDEX idx_rescheduling_proposal_tenant_deadline ON commercial_reservation.rescheduling_proposal (tenant_id, response_deadline_at) WHERE proposal_state = 'PENDING';
