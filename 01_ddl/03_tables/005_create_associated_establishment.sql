-- The hotels and restaurants a tenant associates to promote them (HU-COM-002, RF-018). It is promotional
-- material, not an offer: nothing here is reserved or sold, so the table has no room, dish, menu, seat,
-- rate or availability column, and the engine cannot store what has no column (RN-02, AC-02.7).
--
-- Rows are never deleted (RN-07): an association leaves the listing by becoming INACTIVE, which is why
-- the writer role holds no DELETE on this table. The default privileges of 002_grant_writer.sql give a
-- table born later SELECT, INSERT and UPDATE only, and tests/db-ci.sh proves it with the real user.
--
-- Nothing here has a DEFAULT, on purpose: the service decides the id, the status and both timestamps,
-- so a row that forgets one is refused by the engine instead of silently taking a value nobody chose.
-- The initial status is ACTIVE (PDR RF-018), and the service is who sets it.
-- Every column is NOT NULL: the PDR makes the type, the name, the information, the status and the image
-- mandatory (the image lives in associated_establishment_image, see 006). The two closed value sets are
-- CHECKs and not ENUMs or a catalog table, so a new value is a migration of one constraint (plan.md D-03).
-- The image points at this table with a foreign key (04_alter), so this table holds no image column.
CREATE TABLE commercial_reservation.associated_establishment (
    association_id         uuid        NOT NULL,
    tenant_id              uuid        NOT NULL,
    establishment_type     text        NOT NULL,
    commercial_name        text        NOT NULL,
    commercial_information text        NOT NULL,
    association_status     text        NOT NULL,
    created_at             timestamptz NOT NULL,
    updated_at             timestamptz NOT NULL,
    CONSTRAINT pk_associated_establishment PRIMARY KEY (association_id),
    CONSTRAINT chk_associated_establishment_establishment_type CHECK (establishment_type IN ('HOTEL', 'RESTAURANT')),
    CONSTRAINT chk_associated_establishment_commercial_name_length CHECK (char_length(commercial_name) BETWEEN 1 AND 255),
    CONSTRAINT chk_associated_establishment_association_status CHECK (association_status IN ('ACTIVE', 'INACTIVE'))
);
