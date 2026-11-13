-- HU-COM-002 (-db) spec 2026-11-12 (PROPOSED, AC-D2.12, AC-D2.13): the change log of the associated establishments, one row per registration, inactivation or reactivation (PDR RF-018: both actions leave a
-- trace). It keeps the event, the reason, the actor and the instant, so the portal can draw "Bitacora de cambios". The row is a fact: appended and never edited, so UPDATE is withdrawn in 03_dcl/01_grants/019
-- and DELETE was never granted (RN-07). The reason is required for an inactivation and a reactivation (1 to 500 characters, not blank) and absent for the registration. The association is a real foreign key:
-- the child may point at its parent, the parent still holds none. No DEFAULT anywhere: the service states every value.
CREATE TABLE commercial_reservation.associated_establishment_change (
    change_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_associated_establishment_change_tenant_required NOT NULL,
    association_id uuid CONSTRAINT chk_associated_establishment_change_association_required NOT NULL,
    event_type text CONSTRAINT chk_associated_establishment_change_event_required NOT NULL,
    reason text,
    actor_id uuid CONSTRAINT chk_associated_establishment_change_actor_required NOT NULL,
    occurred_at timestamptz CONSTRAINT chk_associated_establishment_change_occurred_at_required NOT NULL,
    CONSTRAINT pk_associated_establishment_change PRIMARY KEY (change_id),
    CONSTRAINT fk_associated_establishment_change_association FOREIGN KEY (association_id)
        REFERENCES commercial_reservation.associated_establishment (association_id) ON DELETE RESTRICT,
    CONSTRAINT chk_associated_establishment_change_event_type CHECK (event_type IN ('REGISTERED', 'INACTIVATED', 'REACTIVATED')),
    CONSTRAINT chk_associated_establishment_change_reason CHECK (
        (event_type = 'REGISTERED' AND reason IS NULL)
        OR (event_type IN ('INACTIVATED', 'REACTIVATED') AND reason IS NOT NULL AND char_length(btrim(reason)) BETWEEN 1 AND 500 AND char_length(reason) <= 500))
);
