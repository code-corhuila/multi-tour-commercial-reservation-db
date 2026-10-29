-- HU-COM-009 (-db) plan D-04, ADR-005 E6 (PROPOSED): the proof of a transfer, one file per attempt, content in the database (inside the daily dump).
-- The row tells the truth about the bytes: declared type in the three allowed ones, size equal to the length of the content and at most 5 MiB,
-- SHA-256 as 64 lowercase hexadecimal characters. The engine cannot check the signature of the bytes (the -api does) nor that the attempt is a
-- transfer. No creation time (DP-D9-9): the registered_at of the attempt serves. The content is not encrypted (DP-D9-8, debt DD-6).
CREATE TABLE commercial_reservation.payment_proof_file (
    payment_proof_file_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_payment_proof_file_tenant_required NOT NULL,
    payment_attempt_id uuid CONSTRAINT chk_payment_proof_file_payment_attempt_required NOT NULL,
    content bytea CONSTRAINT chk_payment_proof_file_content_required NOT NULL,
    content_type text CONSTRAINT chk_payment_proof_file_content_type_required NOT NULL,
    size_bytes integer CONSTRAINT chk_payment_proof_file_size_required NOT NULL,
    sha256 text CONSTRAINT chk_payment_proof_file_sha256_required NOT NULL,
    CONSTRAINT pk_payment_proof_file PRIMARY KEY (payment_proof_file_id),
    CONSTRAINT uq_payment_proof_file_payment_attempt UNIQUE (payment_attempt_id),
    CONSTRAINT fk_payment_proof_file_payment_attempt FOREIGN KEY (payment_attempt_id)
        REFERENCES commercial_reservation.payment_attempt (payment_attempt_id) ON DELETE RESTRICT,
    CONSTRAINT chk_payment_proof_file_content_type CHECK (content_type IN ('application/pdf', 'image/jpeg', 'image/png')),
    CONSTRAINT chk_payment_proof_file_size CHECK (size_bytes BETWEEN 1 AND 5242880 AND size_bytes = octet_length(content)),
    CONSTRAINT chk_payment_proof_file_sha256 CHECK (sha256 ~ '^[0-9a-f]{64}$')
);
