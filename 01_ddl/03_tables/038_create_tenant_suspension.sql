-- HU-COM-020 (-db) plan D-02 (PROPOSED defaults, DP-D20-1, DP-D20-2, DP-D20-4): one row per period of inactivity of a tenant, written from the events of the tenant, so a mark computed later (the review of a
-- proof, a 24-hour decision) can exclude it. resumed_at and its event are null while the period is open. The key to tenant_status is allowed (same schema). The ids of the opening and closing events are
-- unique, so an event applies once (ADR-004 D4). The row is updated once, to close it, by the guard of 09_triggers/013, and never deleted (the grant does not exist). No DEFAULT anywhere.
CREATE TABLE commercial_reservation.tenant_suspension (
    tenant_suspension_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_tenant_suspension_tenant_required NOT NULL,
    suspended_at timestamptz CONSTRAINT chk_tenant_suspension_suspended_at_required NOT NULL,
    resumed_at timestamptz,
    suspended_by_event_id uuid CONSTRAINT chk_tenant_suspension_opening_event_required NOT NULL,
    resumed_by_event_id uuid,
    CONSTRAINT pk_tenant_suspension PRIMARY KEY (tenant_suspension_id),
    CONSTRAINT fk_tenant_suspension_tenant_status FOREIGN KEY (tenant_id)
        REFERENCES commercial_reservation.tenant_status (tenant_id) ON DELETE RESTRICT,
    CONSTRAINT uq_tenant_suspension_opening_event UNIQUE (suspended_by_event_id),
    CONSTRAINT uq_tenant_suspension_closing_event UNIQUE (resumed_by_event_id),
    CONSTRAINT chk_tenant_suspension_period CHECK (resumed_at IS NULL OR resumed_at >= suspended_at),
    CONSTRAINT chk_tenant_suspension_close_complete CHECK ((resumed_at IS NULL) = (resumed_by_event_id IS NULL))
);
