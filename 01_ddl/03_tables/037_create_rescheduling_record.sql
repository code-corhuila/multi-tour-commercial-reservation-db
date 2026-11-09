-- HU-COM-018 (-db) plan D-04 (PROPOSED defaults, DP-D18-1, DP-D18-4): the agreed change of a rescheduling, one row per episode (the unique key), appended and never edited (RN-EJE-006). It keeps the
-- original reservation, the departure and the start agreed, who approved (the account of whoever answered or recorded the acceptance) and when. linked_reservation_id has no writer yet (DP-02, a new
-- main service or condition is not built) and may never equal the original. The application user inherits the writer, so UPDATE is withdrawn in 03_dcl/01_grants/018 and DELETE was never granted.
-- agreed_salida_id has no foreign key (another domain). No DEFAULT anywhere.
CREATE TABLE commercial_reservation.rescheduling_record (
    rescheduling_record_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_rescheduling_record_tenant_required NOT NULL,
    rescheduling_episode_id uuid CONSTRAINT chk_rescheduling_record_episode_required NOT NULL,
    original_reservation_id uuid CONSTRAINT chk_rescheduling_record_original_required NOT NULL,
    linked_reservation_id uuid,
    agreed_salida_id uuid CONSTRAINT chk_rescheduling_record_salida_required NOT NULL,
    agreed_start_at timestamptz CONSTRAINT chk_rescheduling_record_start_required NOT NULL,
    approved_by uuid CONSTRAINT chk_rescheduling_record_approver_required NOT NULL,
    recorded_at timestamptz CONSTRAINT chk_rescheduling_record_recorded_at_required NOT NULL,
    CONSTRAINT pk_rescheduling_record PRIMARY KEY (rescheduling_record_id),
    CONSTRAINT uq_rescheduling_record_episode UNIQUE (rescheduling_episode_id),
    CONSTRAINT fk_rescheduling_record_episode FOREIGN KEY (rescheduling_episode_id)
        REFERENCES commercial_reservation.rescheduling_episode (rescheduling_episode_id) ON DELETE RESTRICT,
    CONSTRAINT fk_rescheduling_record_original FOREIGN KEY (original_reservation_id)
        REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT,
    CONSTRAINT fk_rescheduling_record_linked FOREIGN KEY (linked_reservation_id)
        REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT,
    CONSTRAINT chk_rescheduling_record_linked CHECK (linked_reservation_id IS NULL OR linked_reservation_id <> original_reservation_id)
);
