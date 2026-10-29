-- HU-COM-005 (-db) DP-D5-7 (default, PROPOSED 2026-10-28): the activity requirements of a companion
-- live apart from the ordinary row, revoked from the reader in dcl-grants-005. Versioned JSON envelope
-- written encrypted by the application (DP-D5-1). No consent column (open). No DEFAULT; no DELETE.
CREATE TABLE commercial_reservation.reservation_companion_sensitive_data (
    reservation_companion_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_reservation_companion_sensitive_data_tenant_required NOT NULL,
    activity_requirements jsonb CONSTRAINT chk_reservation_companion_sensitive_data_requirements_required NOT NULL,
    CONSTRAINT pk_reservation_companion_sensitive_data PRIMARY KEY (reservation_companion_id),
    CONSTRAINT fk_reservation_companion_sensitive_data_companion FOREIGN KEY (reservation_companion_id)
        REFERENCES commercial_reservation.reservation_companion (reservation_companion_id) ON DELETE RESTRICT
);
