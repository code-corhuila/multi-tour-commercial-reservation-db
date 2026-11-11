-- HU-COM-001 (-db) task T-05, PDR RF-004, decision of 2026-10-30 (PROPOSED): the catalog settings of a tenant, one row per tenant.
-- collaborator_editing says whether a Collaborator may edit the descriptive fields of a catalog service; it is false by default and
-- only the Tenant Administrator changes it. A tenant without a row has the flag off, so nothing is seeded. tenant_id is the key and has
-- no foreign key: tenants belongs to another domain (ADR-003), as in tenant_status. Default writer privileges give SELECT, INSERT and
-- UPDATE and never DELETE. updated_by is the user that last set the flag, for the audit trail.
CREATE TABLE commercial_reservation.tenant_catalog_settings (
    tenant_id uuid CONSTRAINT chk_tenant_catalog_settings_tenant_required NOT NULL,
    collaborator_editing boolean CONSTRAINT chk_tenant_catalog_settings_collaborator_editing_required NOT NULL DEFAULT false,
    updated_by uuid CONSTRAINT chk_tenant_catalog_settings_updated_by_required NOT NULL,
    created_at timestamptz CONSTRAINT chk_tenant_catalog_settings_created_at_required NOT NULL,
    updated_at timestamptz CONSTRAINT chk_tenant_catalog_settings_updated_at_required NOT NULL,
    CONSTRAINT pk_tenant_catalog_settings PRIMARY KEY (tenant_id)
);
