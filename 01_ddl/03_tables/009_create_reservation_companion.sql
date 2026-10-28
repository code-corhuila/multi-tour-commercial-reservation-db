-- HU-COM-005 (-db) T-03: only the columns of data-dictionary.md whose decision is closed.
-- Not built because their decision is open: document and birth date or age (DP-D5-1, 2, 5), contact
-- (DP-D5-9), activity requirements (DP-D5-7). The foreign key to the reservation table waits for
-- HU-COM-007 (plan.md D-08), as the outbox service_id waited for the catalog in HU-COM-001.
-- No DEFAULT; the writer never gets DELETE (AC-D5.9).
CREATE TABLE commercial_reservation.reservation_companion (
    reservation_companion_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_reservation_companion_tenant_required NOT NULL,
    reservation_id uuid NOT NULL,
    full_name text CONSTRAINT chk_reservation_companion_full_name_required NOT NULL,
    CONSTRAINT pk_reservation_companion PRIMARY KEY (reservation_companion_id)
);
