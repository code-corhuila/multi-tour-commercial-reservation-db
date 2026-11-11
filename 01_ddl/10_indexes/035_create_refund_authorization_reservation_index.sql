-- HU-COM-016 (-db) plan D-05, AC-D16.13: the refunds of one reservation inside a tenant.
CREATE INDEX idx_refund_authorization_tenant_reservation ON commercial_reservation.refund_authorization (tenant_id, reservation_id);
