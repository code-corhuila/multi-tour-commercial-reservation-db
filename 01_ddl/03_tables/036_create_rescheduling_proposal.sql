-- HU-COM-018 (-db) plan D-03 (PROPOSED defaults, DP-D18-1, DP-D18-2, DP-D18-6): one row per proposal of a new departure; a voided proposal is followed by a substitute, so the history is the rows.
-- A pending proposal has no answer and no closing instant. An accepted or rejected one carries its source (CUSTOMER or OUTSIDE_CHANNEL), when it was answered, who recorded it and when, and
-- its closing instant; an outside answer also names one of four channels and a non-blank evidence of at most 500 characters, a customer answer names neither. A void or expired one has a
-- closing instant and no answer. The remaining minutes exist only while the clock of a pending proposal is frozen. proposed_salida_id has no foreign key (another domain). The key of the
-- request is the existing idempotency_key table (AC-D18.15). No DEFAULT anywhere.
CREATE TABLE commercial_reservation.rescheduling_proposal (
    rescheduling_proposal_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_rescheduling_proposal_tenant_required NOT NULL,
    rescheduling_episode_id uuid CONSTRAINT chk_rescheduling_proposal_episode_required NOT NULL,
    reservation_id uuid CONSTRAINT chk_rescheduling_proposal_reservation_required NOT NULL,
    proposed_salida_id uuid CONSTRAINT chk_rescheduling_proposal_salida_required NOT NULL,
    party_size integer CONSTRAINT chk_rescheduling_proposal_party_required NOT NULL,
    proposed_by uuid CONSTRAINT chk_rescheduling_proposal_author_required NOT NULL,
    proposed_at timestamptz CONSTRAINT chk_rescheduling_proposal_proposed_at_required NOT NULL,
    response_deadline_at timestamptz CONSTRAINT chk_rescheduling_proposal_deadline_required NOT NULL,
    proposal_state text CONSTRAINT chk_rescheduling_proposal_state_required NOT NULL,
    remaining_response_minutes integer,
    answer_source text,
    answer_channel text,
    answer_evidence text,
    answered_at timestamptz,
    answer_recorded_by uuid,
    answer_recorded_at timestamptz,
    closed_at timestamptz,
    CONSTRAINT pk_rescheduling_proposal PRIMARY KEY (rescheduling_proposal_id),
    CONSTRAINT fk_rescheduling_proposal_episode FOREIGN KEY (rescheduling_episode_id)
        REFERENCES commercial_reservation.rescheduling_episode (rescheduling_episode_id) ON DELETE RESTRICT,
    CONSTRAINT fk_rescheduling_proposal_reservation FOREIGN KEY (reservation_id)
        REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT,
    CONSTRAINT chk_rescheduling_proposal_state CHECK (proposal_state IN ('PENDING', 'ACCEPTED', 'REJECTED', 'VOID', 'EXPIRED')),
    CONSTRAINT chk_rescheduling_proposal_party_size CHECK (party_size > 0),
    CONSTRAINT chk_rescheduling_proposal_answer CHECK (
        (proposal_state = 'PENDING' AND answer_source IS NULL AND answered_at IS NULL AND answer_recorded_by IS NULL AND answer_recorded_at IS NULL AND closed_at IS NULL)
        OR (proposal_state IN ('ACCEPTED', 'REJECTED') AND answer_source IS NOT NULL AND answered_at IS NOT NULL AND answer_recorded_by IS NOT NULL AND answer_recorded_at IS NOT NULL AND closed_at IS NOT NULL)
        OR (proposal_state IN ('VOID', 'EXPIRED') AND answer_source IS NULL AND answered_at IS NULL AND answer_recorded_by IS NULL AND answer_recorded_at IS NULL AND closed_at IS NOT NULL)),
    CONSTRAINT chk_rescheduling_proposal_source CHECK (
        (answer_source IS NULL AND answer_channel IS NULL AND answer_evidence IS NULL)
        OR (answer_source = 'CUSTOMER' AND answer_channel IS NULL AND answer_evidence IS NULL)
        OR (answer_source = 'OUTSIDE_CHANNEL' AND answer_channel IN ('EMAIL', 'PHONE', 'WHATSAPP', 'IN_PERSON')
            AND answer_evidence IS NOT NULL AND btrim(answer_evidence) <> '' AND char_length(answer_evidence) <= 500)),
    CONSTRAINT chk_rescheduling_proposal_remaining CHECK (remaining_response_minutes IS NULL OR (proposal_state = 'PENDING' AND remaining_response_minutes >= 0))
);
