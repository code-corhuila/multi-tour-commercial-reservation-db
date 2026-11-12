-- HU-SEC-005 AC4 and HU-SEC-006 AC7 -db spec 022 (PROPOSED): the cutoff per revoked account (ADR-004 D5). account_id is the key, the same value as the sub of the tokens of the account, and has no foreign key:
-- accounts belong to security (ADR-003). tenant_id is optional because the account of a Platform Administrator has no tenant, and has no foreign key because the event can arrive before the tenant copy.
-- No DEFAULT: the service states every instant. The rows are written only by the -api route; nothing is seeded. The idempotency by event id is processed_event, not this table.
CREATE TABLE commercial_reservation.account_session_cutoff (
    account_id uuid NOT NULL,
    tenant_id uuid,
    revoked_from timestamptz NOT NULL,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    CONSTRAINT pk_account_session_cutoff PRIMARY KEY (account_id),
    CONSTRAINT chk_account_session_cutoff_account_id_required CHECK (account_id IS NOT NULL),
    CONSTRAINT chk_account_session_cutoff_revoked_from_required CHECK (revoked_from IS NOT NULL),
    CONSTRAINT chk_account_session_cutoff_created_at_required CHECK (created_at IS NOT NULL),
    CONSTRAINT chk_account_session_cutoff_updated_at_required CHECK (updated_at IS NOT NULL)
);
