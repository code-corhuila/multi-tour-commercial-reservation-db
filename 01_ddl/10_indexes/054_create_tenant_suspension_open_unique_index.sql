-- HU-COM-020 (-db) plan D-02, AC-D20.3: one open suspension per tenant; it also serves the lookup of the open one before every decision of an inactive tenant.
CREATE UNIQUE INDEX uq_tenant_suspension_open_tenant ON commercial_reservation.tenant_suspension (tenant_id) WHERE resumed_at IS NULL;
