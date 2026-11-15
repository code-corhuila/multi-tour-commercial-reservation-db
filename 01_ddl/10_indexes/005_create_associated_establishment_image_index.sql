-- The image of one association inside one tenant. tenant_id leads so that no query can read across tenants,
-- and the index also covers the foreign key column (Annex A rule 3).
CREATE INDEX idx_associated_establishment_image_tenant_id_association_id ON commercial_reservation.associated_establishment_image (tenant_id, association_id);
