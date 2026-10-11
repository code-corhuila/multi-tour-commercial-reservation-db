-- The promotional image of an association, in a table of its own. PROPOSED (plan.md D-02, ADR-004 D4), not
-- decided by 06-data: ADR-005 E6 says the image goes in "the same files table" as the transfer proof, but
-- payment_proof_files is bound to a payment attempt and has no migration. This table uses the same
-- mechanism (bytes in bytea, type, size, checksum, tenant, one row per owner) and does not reuse that
-- table, so neither file's rules (private proof, public image) leak into the other.
-- It is a table apart from associated_establishment so that reading an association never carries up to
-- 800 KB with it.
--
-- One image per association: association_id is UNIQUE, and it is NOT NULL, so no image exists that nothing
-- shows (RN-09). The foreign key to associated_establishment arrives in 04_alter.
-- The engine is only the second line for RN-08 (plan.md D-06): it refuses a size above 800 KB (819200
-- bytes) and a type outside PNG, JPEG and WebP, so SVG cannot be stored. It does not read the bytes, so a
-- renamed SVG sent as image/png is the adapter's to refuse.
-- sha256 is char(64) of lowercase hexadecimal, the form the data dictionary calls Text: a fixed width, and a
-- CHECK so that a value which is not a SHA-256 digest cannot be stored.
-- No DEFAULT anywhere, and no DELETE for the writer role, as in associated_establishment.
CREATE TABLE commercial_reservation.associated_establishment_image (
    image_id       uuid     NOT NULL,
    tenant_id      uuid     NOT NULL,
    association_id uuid     NOT NULL,
    content        bytea    NOT NULL,
    content_type   text     NOT NULL,
    size_bytes     integer  NOT NULL,
    sha256         char(64) NOT NULL,
    CONSTRAINT pk_associated_establishment_image PRIMARY KEY (image_id),
    CONSTRAINT uq_associated_establishment_image_association_id UNIQUE (association_id),
    CONSTRAINT chk_associated_establishment_image_content_type CHECK (content_type IN ('image/png', 'image/jpeg', 'image/webp')),
    CONSTRAINT chk_associated_establishment_image_size_bytes CHECK (size_bytes > 0 AND size_bytes <= 819200),
    CONSTRAINT chk_associated_establishment_image_sha256 CHECK (sha256 ~ '^[0-9a-f]{64}$')
);
