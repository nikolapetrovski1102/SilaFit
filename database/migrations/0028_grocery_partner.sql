-- A grocery partner (paket.mk first): a provider that sells the ingredients of
-- a recipe or a diet plan's shopping list. When an active one is flagged
-- ordersingredients, the app shows "Order the ingredients" on recipes, the
-- diet plan shopping list and after a barcode scan, with the partner's code
-- copied for checkout. searchurl is the partner's product search with {query}
-- where the search text goes (https://example.mk/search?q={query}); without
-- it, the app opens shopurl.
--
-- barcodecatalog*: the partner's product API, asked about a scanned barcode
-- after our own catalog and before Open Food Facts. barcodecatalogurl has
-- {barcode} where the code goes; the key is sent as a Bearer token and never
-- read back by the console. Switched on from the console, independent of
-- whether the provider shows in the app.
ALTER TABLE dbo.supplementproviders
    ADD COLUMN ordersingredients boolean DEFAULT false NOT NULL,
    ADD COLUMN searchurl varchar(500) COLLATE ci,
    ADD COLUMN barcodecatalogenabled boolean DEFAULT false NOT NULL,
    ADD COLUMN barcodecatalogurl varchar(500),
    ADD COLUMN barcodecatalogapikey varchar(500);

-- Ready but off: the console flips "Show in the app" once the deal is live and
-- the code is filled in.
INSERT INTO dbo.supplementproviders
    (name, tagline, shopurl, category, isactive, sortorder, ordersingredients)
SELECT 'Paket.mk', 'Groceries delivered to your door', 'https://paket.mk/', 'Food', false,
       COALESCE((SELECT MAX(sortorder) + 1 FROM dbo.supplementproviders), 0), true
WHERE NOT EXISTS (SELECT 1 FROM dbo.supplementproviders WHERE name = 'Paket.mk');
