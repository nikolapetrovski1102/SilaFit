-- Seven system meal suggestions: five high-protein breakfasts and two sardine
-- wraps for lunch. Macros are per serving; ingredients and steps are stored in
-- mealsuggestioningredients / mealsuggestioninstructions like the imported
-- recipe library.

INSERT INTO dbo.mealsuggestions
    (mealsuggestionid, title, mealtype, description, calorieskcal, proteing, carbsg, fatsg,
     issystemdefault, sortorder, categoriesjson)
VALUES
    ('58e9ddd8-70af-479a-b980-2c1c21933ca6', 'Protein Oatmeal with Banana-Peanut Butter Cream', 'Breakfast',
     'High-protein breakfast with 39 g protein per serving.', 553, 39, 66, 17,
     true, 10200, '["High Protein Recipes","Vegetarian Recipes","Breakfast Recipes"]'),
    ('20171db0-e429-416d-a72e-3ebf332a9176', 'Protein Quinoa Bowl with Cinnamon Apple and Blueberries', 'Breakfast',
     'High-protein breakfast with 34 g protein per serving.', 461, 34, 60, 13,
     true, 10201, '["High Protein Recipes","Vegetarian Recipes","Breakfast Recipes"]'),
    ('2a1c59c9-96b8-4314-917a-96d8ab4f8f45', 'Protein Yogurt Bowl with Pan-Fried Apple', 'Breakfast',
     'High-protein breakfast with 39 g protein per serving.', 536, 39, 73, 11,
     true, 10202, '["High Protein Recipes","Vegetarian Recipes","Breakfast Recipes"]'),
    ('2515ead9-4133-47b2-a6b6-183e896b54a1', 'Almond Banana Bread with Protein Yogurt Topping', 'Breakfast',
     'High-protein breakfast with 37 g protein per serving.', 527, 37, 51, 19,
     true, 10203, '["High Protein Recipes","Vegetarian Recipes","Breakfast Recipes"]'),
    ('18b3e111-02ad-498e-b342-49bfefe1f64f', 'Banana Oat Pancakes with Protein Glaze', 'Breakfast',
     'High-protein breakfast with 39 g protein per serving.', 510, 39, 54, 17,
     true, 10204, '["High Protein Recipes","Vegetarian Recipes","Breakfast Recipes"]'),
    ('e89b7b34-27fd-4c2f-8067-9ae2d26c18ea', 'Sardine, Hummus and Bean Tortilla', 'Lunch',
     'High-protein lunch with 31 g protein per serving.', 570, 31, 48, 28,
     true, 10205, '["High Protein Recipes","Lunch Recipes"]'),
    ('afefb63e-cadc-4132-9a0c-8a6134166d61', 'Sardine Avocado Hummus Wrap', 'Lunch',
     'High-protein lunch with 34 g protein per serving.', 650, 34, 38, 41,
     true, 10206, '["High Protein Recipes","Lunch Recipes"]');

INSERT INTO dbo.mealsuggestioningredients (mealsuggestionid, sortorder, ingredienttext)
VALUES
    ('58e9ddd8-70af-479a-b980-2c1c21933ca6', 1, '60 g rolled oats'),
    ('58e9ddd8-70af-479a-b980-2c1c21933ca6', 2, '1 scoop protein powder'),
    ('58e9ddd8-70af-479a-b980-2c1c21933ca6', 3, '1 tbsp chia seeds'),
    ('58e9ddd8-70af-479a-b980-2c1c21933ca6', 4, '1 cup plant-based milk'),
    ('58e9ddd8-70af-479a-b980-2c1c21933ca6', 5, '1/2 banana'),
    ('58e9ddd8-70af-479a-b980-2c1c21933ca6', 6, '1 tbsp peanut butter'),
    ('58e9ddd8-70af-479a-b980-2c1c21933ca6', 7, '1/2 cup crushed raspberries'),
    ('58e9ddd8-70af-479a-b980-2c1c21933ca6', 8, 'Shredded coconut (optional)'),

    ('20171db0-e429-416d-a72e-3ebf332a9176', 1, '50 g quinoa (dry weight), cooked'),
    ('20171db0-e429-416d-a72e-3ebf332a9176', 2, '1 scoop protein powder'),
    ('20171db0-e429-416d-a72e-3ebf332a9176', 3, '20-40 ml plant-based milk'),
    ('20171db0-e429-416d-a72e-3ebf332a9176', 4, '1 apple'),
    ('20171db0-e429-416d-a72e-3ebf332a9176', 5, '1 tsp coconut oil'),
    ('20171db0-e429-416d-a72e-3ebf332a9176', 6, '1 tsp cinnamon'),
    ('20171db0-e429-416d-a72e-3ebf332a9176', 7, '1 handful blueberries'),
    ('20171db0-e429-416d-a72e-3ebf332a9176', 8, '6 chopped hazelnuts or 1 small tsp nut butter'),

    ('2a1c59c9-96b8-4314-917a-96d8ab4f8f45', 1, '1 scoop protein powder'),
    ('2a1c59c9-96b8-4314-917a-96d8ab4f8f45', 2, '50 g unsweetened cornflakes'),
    ('2a1c59c9-96b8-4314-917a-96d8ab4f8f45', 3, '1 apple'),
    ('2a1c59c9-96b8-4314-917a-96d8ab4f8f45', 4, '100 g Greek yogurt'),
    ('2a1c59c9-96b8-4314-917a-96d8ab4f8f45', 5, '1 tsp peanut butter'),
    ('2a1c59c9-96b8-4314-917a-96d8ab4f8f45', 6, '1 tsp cinnamon'),
    ('2a1c59c9-96b8-4314-917a-96d8ab4f8f45', 7, '1 tsp coconut oil, melted'),

    ('2515ead9-4133-47b2-a6b6-183e896b54a1', 1, '2 slices almond banana bread'),
    ('2515ead9-4133-47b2-a6b6-183e896b54a1', 2, '100 g Greek yogurt'),
    ('2515ead9-4133-47b2-a6b6-183e896b54a1', 3, '2/3 scoop protein powder'),
    ('2515ead9-4133-47b2-a6b6-183e896b54a1', 4, '5 tbsp pomegranate seeds'),

    ('18b3e111-02ad-498e-b342-49bfefe1f64f', 1, '1 egg'),
    ('18b3e111-02ad-498e-b342-49bfefe1f64f', 2, '30 g rolled oats'),
    ('18b3e111-02ad-498e-b342-49bfefe1f64f', 3, '2/3 banana'),
    ('18b3e111-02ad-498e-b342-49bfefe1f64f', 4, '1 tsp cinnamon'),
    ('18b3e111-02ad-498e-b342-49bfefe1f64f', 5, '1 tsp vanilla extract'),
    ('18b3e111-02ad-498e-b342-49bfefe1f64f', 6, '1/2 tsp baking powder'),
    ('18b3e111-02ad-498e-b342-49bfefe1f64f', 7, 'Pinch of salt'),
    ('18b3e111-02ad-498e-b342-49bfefe1f64f', 8, '1 scoop protein powder (for the glaze)'),
    ('18b3e111-02ad-498e-b342-49bfefe1f64f', 9, 'Splash of plant-based milk or water (for the glaze)'),
    ('18b3e111-02ad-498e-b342-49bfefe1f64f', 10, '1 kiwi'),

    ('e89b7b34-27fd-4c2f-8067-9ae2d26c18ea', 1, '1 can sardines, drained'),
    ('e89b7b34-27fd-4c2f-8067-9ae2d26c18ea', 2, '30 g hummus'),
    ('e89b7b34-27fd-4c2f-8067-9ae2d26c18ea', 3, '100 g red kidney beans'),
    ('e89b7b34-27fd-4c2f-8067-9ae2d26c18ea', 4, 'Arugula'),
    ('e89b7b34-27fd-4c2f-8067-9ae2d26c18ea', 5, '1 carrot'),
    ('e89b7b34-27fd-4c2f-8067-9ae2d26c18ea', 6, '3-4 radishes'),
    ('e89b7b34-27fd-4c2f-8067-9ae2d26c18ea', 7, '1 tortilla (ideally with a short, additive-free ingredient list)'),

    ('afefb63e-cadc-4132-9a0c-8a6134166d61', 1, '1 tortilla (60 g)'),
    ('afefb63e-cadc-4132-9a0c-8a6134166d61', 2, '70 g high-protein hummus'),
    ('afefb63e-cadc-4132-9a0c-8a6134166d61', 3, '1 can sardines, well drained'),
    ('afefb63e-cadc-4132-9a0c-8a6134166d61', 4, '1/3 avocado'),
    ('afefb63e-cadc-4132-9a0c-8a6134166d61', 5, 'Lettuce');

INSERT INTO dbo.mealsuggestioninstructions (mealsuggestionid, sortorder, instructiontext)
VALUES
    ('58e9ddd8-70af-479a-b980-2c1c21933ca6', 1, 'Simmer the oats and chia seeds in 2 cups of water over low heat until thick and swollen, adding a little more water if needed.'),
    ('58e9ddd8-70af-479a-b980-2c1c21933ca6', 2, 'Take the pot off the heat and stir in the protein powder and plant-based milk until smooth.'),
    ('58e9ddd8-70af-479a-b980-2c1c21933ca6', 3, 'Blend the banana with the peanut butter into a smooth cream, loosening it with a splash of milk or water if it is too thick.'),
    ('58e9ddd8-70af-479a-b980-2c1c21933ca6', 4, 'Spoon the oats into a bowl, spread the banana cream on top and finish with the raspberries (or other seasonal fruit) and coconut.'),

    ('20171db0-e429-416d-a72e-3ebf332a9176', 1, 'Cook the quinoa according to the package instructions; it can be cooked the night before to save time.'),
    ('20171db0-e429-416d-a72e-3ebf332a9176', 2, 'Stir the protein powder into the warm quinoa with enough plant-based milk to make it creamy.'),
    ('20171db0-e429-416d-a72e-3ebf332a9176', 3, 'Dice the apple and cook it in the coconut oil with the cinnamon until soft and golden.'),
    ('20171db0-e429-416d-a72e-3ebf332a9176', 4, 'Top the quinoa with the apple, blueberries and hazelnuts or nut butter.'),

    ('2a1c59c9-96b8-4314-917a-96d8ab4f8f45', 1, 'Dice the apple and pan-fry it in the melted coconut oil with the cinnamon until caramelised.'),
    ('2a1c59c9-96b8-4314-917a-96d8ab4f8f45', 2, 'Mix the Greek yogurt with the protein powder, adding a little water to reach the thickness you like, then fold in the cornflakes.'),
    ('2a1c59c9-96b8-4314-917a-96d8ab4f8f45', 3, 'Top with the warm apple and drizzle with the peanut butter.'),

    ('2515ead9-4133-47b2-a6b6-183e896b54a1', 1, 'Whisk the Greek yogurt with the protein powder into a thick, smooth cream.'),
    ('2515ead9-4133-47b2-a6b6-183e896b54a1', 2, 'Spread the cream over the banana bread slices and scatter the pomegranate seeds on top.'),

    ('18b3e111-02ad-498e-b342-49bfefe1f64f', 1, 'Blend the egg, oats, banana, cinnamon, vanilla, baking powder and salt into a batter, adding water if it is too thick. Let it rest for 10 minutes if you have time.'),
    ('18b3e111-02ad-498e-b342-49bfefe1f64f', 2, 'Cook small pancakes in a pan lightly wiped with oil on a paper towel rather than poured in.'),
    ('18b3e111-02ad-498e-b342-49bfefe1f64f', 3, 'For the glaze, stir the protein powder with a little milk or water using a fork until thick and smooth.'),
    ('18b3e111-02ad-498e-b342-49bfefe1f64f', 4, 'Pour the glaze over the pancakes and serve with the sliced kiwi.'),

    ('e89b7b34-27fd-4c2f-8067-9ae2d26c18ea', 1, 'Warm or lightly toast the tortilla and spread it with the hummus.'),
    ('e89b7b34-27fd-4c2f-8067-9ae2d26c18ea', 2, 'Grate the carrot, slice the radishes and drain the sardines well.'),
    ('e89b7b34-27fd-4c2f-8067-9ae2d26c18ea', 3, 'Layer the sardines, beans, carrot, radishes and plenty of arugula on one half, then fold the tortilla over - it is too full to roll. Spring onion makes a good addition.'),

    ('afefb63e-cadc-4132-9a0c-8a6134166d61', 1, 'Drain the sardines in a sieve and rinse them briefly with water to remove the excess oil.'),
    ('afefb63e-cadc-4132-9a0c-8a6134166d61', 2, 'Lightly toast the tortilla in a pan.'),
    ('afefb63e-cadc-4132-9a0c-8a6134166d61', 3, 'Spread the hummus, then add the sardines, sliced avocado and lettuce, plus any extra vegetables you like, and roll it up.');
