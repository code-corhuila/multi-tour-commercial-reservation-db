-- HU-COM-016 (-db) plan D-05, AC-D16.13: the overdue list is a range read of the refunds not executed and not yet marked, by due instant.
CREATE INDEX idx_refund_authorization_tenant_due ON commercial_reservation.refund_authorization (tenant_id, execution_due_at)
    WHERE execution_state <> 'EXECUTED' AND overdue_marked_at IS NULL;
