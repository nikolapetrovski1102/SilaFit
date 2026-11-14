-- Barcode scanning in the meal tracker: a product photo per food, so a
-- scanned product shows what the user is holding. Filled from Open Food
-- Facts (the importer and the live barcode lookup). User foods stay without
-- one until they can upload their own.
ALTER TABLE dbo.foodnutrition
    ADD COLUMN imageurl varchar(1000) COLLATE ci;
