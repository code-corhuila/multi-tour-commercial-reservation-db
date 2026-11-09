-- HU-COM-018 (-db) plan D-02 (PROPOSED defaults, DP-D18-1): one row per reservation and incident of a departure that cannot run, holding the clocks of the rescheduling. It is the only
-- place where the original departure, the start of the episode, the due instant of the proposal and the freeze of the clocks live. An open episode has no closing instant and no
-- reason; a closed one has both, and RESCHEDULED goes only with ACCEPTED. The freeze pair keeps the remaining minutes while the tenant is inactive (HU-COM-020). original_salida_id has no
-- foreign key: the departure belongs to another domain (Annex J.3.4). Rows are updated forward only by the guard of 09_triggers/011 and never deleted. No DEFAULT anywhere.
CREATE TABLE commercial_reservation.rescheduling_episode (
    rescheduling_episode_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_rescheduling_episode_tenant_required NOT NULL,
    reservation_id uuid CONSTRAINT chk_rescheduling_episode_reservation_required NOT NULL,
    original_salida_id uuid CONSTRAINT chk_rescheduling_episode_original_salida_required NOT NULL,
    episode_started_at timestamptz CONSTRAINT chk_rescheduling_episode_started_required NOT NULL,
    proposal_due_at timestamptz CONSTRAINT chk_rescheduling_episode_due_required NOT NULL,
    episode_state text CONSTRAINT chk_rescheduling_episode_state_required NOT NULL,
    closed_at timestamptz,
    closed_reason text,
    frozen_at timestamptz,
    remaining_episode_minutes integer,
    opened_at timestamptz CONSTRAINT chk_rescheduling_episode_opened_required NOT NULL,
    CONSTRAINT pk_rescheduling_episode PRIMARY KEY (rescheduling_episode_id),
    CONSTRAINT fk_rescheduling_episode_reservation FOREIGN KEY (reservation_id)
        REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT,
    CONSTRAINT uq_rescheduling_episode_reservation_departure UNIQUE (tenant_id, reservation_id, original_salida_id),
    CONSTRAINT chk_rescheduling_episode_state CHECK (episode_state IN ('OPEN', 'RESCHEDULED', 'CANCELLED')),
    CONSTRAINT chk_rescheduling_episode_reason CHECK (closed_reason IS NULL OR closed_reason IN ('ACCEPTED', 'REJECTED_BY_CUSTOMER', 'NO_ALTERNATIVE',
        'PROPOSAL_PERIOD_EXPIRED', 'RESPONSE_DEADLINE_EXPIRED', 'EPISODE_LIMIT_REACHED', 'PROPOSED_DEPARTURE_CANCELLED_WHILE_INACTIVE')),
    CONSTRAINT chk_rescheduling_episode_closing CHECK (episode_state NOT IN ('OPEN', 'RESCHEDULED', 'CANCELLED') OR (
        ((episode_state = 'OPEN') = (closed_at IS NULL AND closed_reason IS NULL))
        AND (episode_state = 'OPEN' OR (closed_at IS NOT NULL AND closed_reason IS NOT NULL))
        AND ((episode_state = 'RESCHEDULED') = (closed_reason = 'ACCEPTED')))),
    CONSTRAINT chk_rescheduling_episode_freeze CHECK ((frozen_at IS NULL) = (remaining_episode_minutes IS NULL) AND (remaining_episode_minutes IS NULL OR remaining_episode_minutes >= 0))
);
