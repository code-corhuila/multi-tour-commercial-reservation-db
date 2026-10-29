-- HU-COM-005 (-db) T-03: only the columns of data-dictionary.md whose decision is closed.
-- Not built because their decision is open (spec section 7): document, birth date or age, e-mail and
-- the keyed hashes (DP-D5-1, 2, 3, 5), terms acceptance (DP-D5-1), status (DP-D5-6), account link
-- (DP-D5-4), retention date (DP-D5-10). Each arrives in its own changeset once decided.
-- Nothing has a DEFAULT: the service decides the id and the creation time. Default privileges give the
-- writer SELECT, INSERT and UPDATE and never DELETE (AC-D5.9).
CREATE TABLE commercial_reservation.customer (
    customer_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_customer_tenant_required NOT NULL,
    full_name text CONSTRAINT chk_customer_full_name_required NOT NULL,
    created_at timestamptz NOT NULL,
    CONSTRAINT pk_customer PRIMARY KEY (customer_id)
);
