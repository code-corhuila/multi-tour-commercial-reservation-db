-- HU-COM-002 (-db): the contact is optional and the service is the only writer; reverting drops the three columns and their checks with the data they hold.
ALTER TABLE commercial_reservation.associated_establishment
    DROP CONSTRAINT chk_associated_establishment_contact_email_length,
    DROP CONSTRAINT chk_associated_establishment_contact_phone_length,
    DROP CONSTRAINT chk_associated_establishment_contact_address_length,
    DROP COLUMN contact_email,
    DROP COLUMN contact_phone,
    DROP COLUMN contact_address;
