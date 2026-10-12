-- The image belongs to an association of this same schema, so the engine holds the relation (plan.md D-05).
-- It lives in 04_alter, as every foreign key of this repository does.
-- RESTRICT: an association that has an image cannot disappear from under it, and nothing in this domain
-- deletes business data. The key is simple, (association_id) alone, because the key of the association is
-- association_id by itself and no UNIQUE carries tenant_id; the tenant of the image is therefore kept by
-- the application, the same debt that spec.md DD-6 records for salida_capacity.
ALTER TABLE commercial_reservation.associated_establishment_image
    ADD CONSTRAINT fk_associated_establishment_image_association FOREIGN KEY (association_id)
    REFERENCES commercial_reservation.associated_establishment (association_id) ON DELETE RESTRICT;
