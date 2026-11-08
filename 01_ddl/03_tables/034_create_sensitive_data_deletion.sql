-- HU-COM-019 (-db) plan D-03, AC-D19.4, AC-D19.5 (DP-D19-2, PROPOSED default): the record of one retention deletion, one row per reservation (the primary key makes a second run on the
-- same reservation a no-op, AC6 of the story). It keeps ids, the anchor instant and its basis, the deletion instant and two counts, and never a name, document, contact or medical
-- value. Append-only: UPDATE is withdrawn in 03_dcl/01_grants/017 and DELETE was never granted. The outbox is purged after publication, so this record is the lasting trace.
-- No DEFAULT. The keys to reservation and customer restrict.
CREATE TABLE commercial_reservation.sensitive_data_deletion (
    reservation_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_sensitive_data_deletion_tenant_required NOT NULL,
    customer_id uuid CONSTRAINT chk_sensitive_data_deletion_customer_required NOT NULL,
    anchor_at timestamptz CONSTRAINT chk_sensitive_data_deletion_anchor_at_required NOT NULL,
    anchor_basis text CONSTRAINT chk_sensitive_data_deletion_anchor_basis_required NOT NULL,
    deleted_at timestamptz CONSTRAINT chk_sensitive_data_deletion_deleted_at_required NOT NULL,
    customer_data_deleted boolean CONSTRAINT chk_sensitive_data_deletion_customer_data_required NOT NULL,
    companion_rows_deleted integer CONSTRAINT chk_sensitive_data_deletion_companion_rows_required NOT NULL,
    CONSTRAINT pk_sensitive_data_deletion PRIMARY KEY (reservation_id),
    CONSTRAINT fk_sensitive_data_deletion_reservation FOREIGN KEY (reservation_id)
        REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT,
    CONSTRAINT fk_sensitive_data_deletion_customer FOREIGN KEY (customer_id)
        REFERENCES commercial_reservation.customer (customer_id) ON DELETE RESTRICT,
    CONSTRAINT chk_sensitive_data_deletion_basis CHECK (anchor_basis IN
        ('SERVICE_END', 'ESTIMATED_END', 'CLOSING', 'CANCELLATION_NO_VALUES', 'CANCELLATION_BLOCKED')),
    CONSTRAINT chk_sensitive_data_deletion_count CHECK (companion_rows_deleted >= 0)
);
