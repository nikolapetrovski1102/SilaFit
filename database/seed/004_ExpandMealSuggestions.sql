USE SilenDb;
GO

-- Expands the "Suggested this month" catalog seeded in 003_SeedMealSuggestions.sql
-- from one flagship dinner-or-similar per month to full coverage: every
-- calendar month now has a Breakfast, Lunch, Dinner, and Snack option, plus
-- a set of evergreen (SuggestedMonth NULL) staples that rotate in every
-- month. Same convention as 003: every macro figure is summed from per-100g
-- USDA FoodData Central (fdc.nal.usda.gov) values at seed-authoring time,
-- not fetched live. Idempotent by Title - safe to re-run.
INSERT INTO dbo.MealSuggestions
    (Title, MealType, Description, CaloriesKcal, ProteinG, CarbsG, FatsG, SuggestedMonth, IsSystemDefault, SortOrder)
SELECT v.Title, v.MealType, v.Description, v.CaloriesKcal, v.ProteinG, v.CarbsG, v.FatsG, v.SuggestedMonth, 1, v.SortOrder
FROM (VALUES
    -- January
    -- oats_cooked 300g + banana 118g + walnuts 20g
    (N'Steel-Cut Oats with Banana & Walnuts', N'Breakfast', N'Warm oats topped with banana and walnuts - a cozy January breakfast.', 449, 12, 66, 18, 1, 13),
    -- lentils 300g + ww_bread 40g + olive_oil 5g
    (N'Hearty Lentil Soup with Crusty Bread', N'Lunch', N'Simmered lentils with a side of crusty whole-wheat bread and olive oil.', 491, 32, 76, 8, 1, 14),
    -- almonds 20g + walnuts 10g + cranberries_dried 15g
    (N'Almond & Cranberry Trail Mix', N'Snack', N'Roasted almonds, walnuts, and dried cranberries.', 230, 6, 18, 17, 1, 15),
    -- February
    -- egg 150g + spinach 40g + feta 20g
    (N'Spinach & Feta Veggie Omelette', N'Breakfast', N'Three-egg omelette with wilted spinach and feta.', 294, 23, 4, 21, 2, 16),
    -- turkey_breast 100g + tortilla_flour 60g + avocado 50g + spinach 20g
    (N'Turkey & Avocado Wrap', N'Lunch', N'Sliced turkey breast with avocado and spinach in a flour tortilla.', 407, 36, 35, 13, 2, 17),
    -- dark_choc70 15g + almonds 20g
    (N'Dark Chocolate & Almonds', N'Snack', N'A square of dark chocolate with roasted almonds.', 206, 5, 11, 16, 2, 18),
    -- March
    -- egg_white 200g + bell_pepper 50g + cheddar 20g
    (N'Egg White Veggie Scramble', N'Breakfast', N'Egg whites scrambled with bell pepper, mushrooms, and cheddar.', 200, 28, 5, 7, 3, 19),
    -- tilapia 150g + quinoa 150g + asparagus 100g + olive_oil 5g
    (N'Herb-Baked Tilapia with Quinoa & Asparagus', N'Dinner', N'Herb-baked tilapia over quinoa with roasted asparagus.', 438, 48, 36, 12, 3, 20),
    -- hummus 60g + carrots 50g + cucumber 50g
    (N'Hummus & Veggie Sticks', N'Snack', N'Hummus with carrot and cucumber sticks.', 125, 6, 14, 6, 3, 21),
    -- April
    -- chickpeas 150g + avocado 70g + tomato 60g + cucumber 60g + olive_oil 5g
    (N'Chickpea & Avocado Salad', N'Lunch', N'Chickpeas, avocado, tomato, and cucumber in olive oil.', 422, 16, 51, 20, 4, 22),
    -- chicken_breast 150g + potato 150g + asparagus 100g + olive_oil 5g
    (N'Lemon Herb Chicken with Asparagus & Potatoes', N'Dinner', N'Lemon herb grilled chicken with asparagus and new potatoes.', 453, 53, 36, 11, 4, 23),
    -- apple 150g + peanut_butter 20g
    (N'Apple with Peanut Butter', N'Snack', N'Sliced apple with peanut butter.', 196, 5, 25, 10, 4, 24),
    -- May
    -- chia 40g + almond_milk 200g + strawberries 80g
    (N'Strawberry Chia Pudding', N'Breakfast', N'Chia seeds soaked in almond milk, topped with strawberries.', 250, 9, 24, 15, 5, 25),
    -- pork_tenderloin 150g + potato 180g + butter 5g + green_beans 100g
    (N'Pan-Seared Pork Tenderloin with Green Beans & Mash', N'Dinner', N'Pan-seared pork tenderloin with mashed potatoes and green beans.', 453, 45, 46, 10, 5, 26),
    -- cottage_lowfat 150g + pineapple 80g
    (N'Cottage Cheese with Pineapple', N'Snack', N'Cottage cheese topped with fresh pineapple.', 148, 18, 15, 2, 5, 27),
    -- June
    -- gy_nonfat 200g + mango 100g + granola 25g
    (N'Tropical Greek Yogurt Bowl', N'Breakfast', N'Greek yogurt with mango and granola.', 296, 23, 38, 6, 6, 28),
    -- tuna_water 120g + avocado 100g + tomato 50g + cucumber 50g
    (N'Tuna Salad Stuffed Avocado', N'Lunch', N'Tuna salad with tomato and cucumber, stuffed into avocado halves.', 316, 34, 13, 16, 6, 29),
    -- watermelon 150g + feta 30g
    (N'Watermelon & Feta Bites', N'Snack', N'Cubed watermelon with feta.', 124, 5, 13, 7, 6, 30),
    -- July
    -- cottage_lowfat 180g + peach 120g + almonds 10g
    (N'Peach & Cottage Cheese Bowl', N'Breakfast', N'Cottage cheese with fresh peach and almonds.', 234, 25, 20, 7, 7, 31),
    -- chicken_breast 160g + corn 100g + bell_pepper 80g + olive_oil 5g
    (N'Grilled Chicken Skewers with Corn & Peppers', N'Dinner', N'Grilled chicken skewers with corn and bell pepper.', 429, 54, 26, 12, 7, 32),
    -- cherries 150g + dark_choc70 15g
    (N'Cherries & Dark Chocolate', N'Snack', N'Fresh cherries with a square of dark chocolate.', 184, 3, 31, 7, 7, 33),
    -- August
    -- shrimp 150g + tortilla_corn 60g + black_beans 100g + salsa 40g
    (N'Grilled Shrimp Taco Bowl', N'Lunch', N'Grilled shrimp with black beans, corn tortillas, and salsa.', 426, 49, 54, 3, 8, 34),
    -- beef_sirloin 150g + zucchini 100g + bell_pepper 80g + onion 50g + olive_oil 10g
    (N'Beef Sirloin with Grilled Vegetables', N'Dinner', N'Grilled beef sirloin with zucchini, bell pepper, and onion.', 427, 43, 13, 22, 8, 35),
    -- figs_fresh 100g + walnuts 15g
    (N'Fig & Walnut Bites', N'Snack', N'Fresh figs with walnuts.', 172, 3, 21, 10, 8, 36),
    -- September
    -- oats_cooked 250g + pumpkin 100g + milk_2pct 100g + walnuts 10g
    (N'Pumpkin Spice Overnight Oats', N'Breakfast', N'Oats with pumpkin, milk, and walnuts.', 327, 12, 45, 12, 9, 37),
    -- chicken_breast 130g + ww_bread 70g + mozzarella_ps 40g + tomato 50g
    (N'Chicken Caprese Sandwich', N'Lunch', N'Grilled chicken with mozzarella and tomato on whole-wheat bread.', 498, 59, 32, 14, 9, 38),
    -- apricots_dried 40g + pecans 15g
    (N'Dried Apricots & Pecans', N'Snack', N'Dried apricots with pecans.', 200, 3, 27, 11, 9, 39),
    -- October
    -- oats_cooked 280g + apple 100g + walnuts 15g
    (N'Apple Cinnamon Oatmeal', N'Breakfast', N'Oats with apple and walnuts.', 349, 10, 50, 14, 10, 40),
    -- butternut 150g + chickpeas 150g + kale 60g + feta 30g + olive_oil 5g
    (N'Butternut Squash & Chickpea Bowl', N'Lunch', N'Roasted butternut squash with chickpeas, kale, and feta.', 446, 20, 61, 16, 10, 41),
    -- pomegranate_seeds 100g + almonds 20g
    (N'Pomegranate & Almonds', N'Snack', N'Pomegranate seeds with roasted almonds.', 199, 6, 23, 11, 10, 42),
    -- November
    -- gy_2pct 200g + pumpkin 80g + pecans 15g
    (N'Pecan Pumpkin Greek Yogurt', N'Breakfast', N'Greek yogurt with pumpkin and pecans.', 277, 20, 17, 15, 11, 43),
    -- turkey_breast 120g + tortilla_flour 60g + cranberries_dried 20g + spinach 20g
    (N'Turkey & Cranberry Wrap', N'Lunch', N'Turkey breast with dried cranberries and spinach in a flour tortilla.', 419, 41, 47, 6, 11, 44),
    -- almonds 15g + walnuts 15g + pecans 10g
    (N'Winter Mixed Nuts', N'Snack', N'Almonds, walnuts, and pecans.', 254, 6, 7, 24, 11, 45),
    -- December
    -- oats_cooked 260g + cranberries_dried 20g + almonds 15g
    (N'Cranberry Almond Overnight Oats', N'Breakfast', N'Oats with dried cranberries and almonds.', 336, 10, 51, 12, 12, 46),
    -- beef_sirloin 120g + carrots 80g + onion 50g + potato 100g
    (N'Beef & Vegetable Soup', N'Lunch', N'Beef sirloin simmered with carrots, onion, and potato.', 363, 36, 32, 9, 12, 47),
    -- dark_choc70 20g + almonds 15g
    (N'Dark Chocolate Almond Bark', N'Snack', N'Dark chocolate with roasted almonds.', 206, 5, 12, 16, 12, 48),
    -- Evergreen (shows every month)
    -- oats_cooked 300g + whey 30g + banana 100g
    (N'Classic Protein Oats & Banana', N'Breakfast', N'Oats mixed with protein powder and banana.', 416, 33, 61, 6, NULL, 49),
    -- egg_white 200g + tortilla_flour 50g + spinach 30g + cheddar 20g
    (N'Veggie Egg White Wrap', N'Breakfast', N'Egg whites with spinach and cheddar in a flour tortilla.', 348, 32, 28, 11, NULL, 50),
    -- ww_bread 60g + peanut_butter 30g + banana 100g
    (N'Peanut Butter Banana Toast', N'Breakfast', N'Whole-wheat toast with peanut butter and banana.', 414, 16, 54, 17, NULL, 51),
    -- gy_nonfat 200g + blueberries 80g + granola 20g + chia 10g
    (N'Berry Protein Smoothie Bowl', N'Breakfast', N'Greek yogurt blended with blueberries, granola, and chia seeds.', 306, 24, 35, 8, NULL, 52),
    -- chicken_breast 150g + brown_rice 150g + broccoli 100g + olive_oil 5g
    (N'Grilled Chicken & Brown Rice Bowl', N'Lunch', N'Grilled chicken breast over brown rice with broccoli.', 495, 53, 43, 12, NULL, 53),
    -- tuna_water 130g + chickpeas 120g + tomato 60g + olive_oil 5g
    (N'Tuna & Chickpea Salad', N'Lunch', N'Tuna with chickpeas, tomato, and olive oil.', 403, 45, 35, 9, NULL, 54),
    -- turkey_breast 100g + ww_bread 70g + cheddar 20g + tomato 40g
    (N'Turkey Club Sandwich', N'Lunch', N'Turkey breast with cheddar and tomato on whole-wheat bread.', 396, 44, 31, 10, NULL, 55),
    -- black_beans 150g + white_rice 150g + corn 60g + salsa 30g
    (N'Black Bean & Rice Power Bowl', N'Lunch', N'Black beans and white rice with corn and salsa.', 461, 20, 93, 2, NULL, 56),
    -- chicken_breast 170g + sweet_potato 180g + broccoli 100g
    (N'Classic Grilled Chicken & Sweet Potato', N'Dinner', N'Grilled chicken breast with roasted sweet potato and broccoli.', 478, 59, 45, 7, NULL, 57),
    -- salmon 150g + brown_rice 150g + green_beans 100g
    (N'Baked Salmon with Brown Rice & Green Beans', N'Dinner', N'Baked salmon over brown rice with green beans.', 512, 39, 44, 20, NULL, 58),
    -- beef_sirloin 150g + bell_pepper 80g + broccoli 80g + white_rice 120g + olive_oil 5g
    (N'Lean Beef Stir-Fry', N'Dinner', N'Beef sirloin stir-fried with bell pepper and broccoli over rice.', 528, 46, 44, 17, NULL, 59),
    -- tofu_firm 180g + broccoli 100g + carrots 60g + brown_rice 150g + olive_oil 5g
    (N'Tofu & Vegetable Stir-Fry', N'Dinner', N'Firm tofu stir-fried with broccoli and carrots over brown rice.', 527, 34, 53, 21, NULL, 60),
    -- whey 30g + almond_milk 250g
    (N'Vanilla Protein Shake', N'Snack', N'Whey protein blended with almond milk.', 152, 26, 4, 4, NULL, 61),
    -- gy_nonfat 170g + almonds 15g
    (N'Greek Yogurt & Almonds', N'Snack', N'Plain Greek yogurt with roasted almonds.', 187, 20, 9, 8, NULL, 62),
    -- egg 100g + apple 120g
    (N'Hard-Boiled Eggs & Apple', N'Snack', N'Two hard-boiled eggs with a sliced apple.', 217, 13, 18, 11, NULL, 63),
    -- cottage_lowfat 150g + blueberries 60g + strawberries 60g
    (N'Mixed Berries & Cottage Cheese', N'Snack', N'Cottage cheese with blueberries and strawberries.', 161, 19, 18, 2, NULL, 64)
) AS v(Title, MealType, Description, CaloriesKcal, ProteinG, CarbsG, FatsG, SuggestedMonth, SortOrder)
WHERE NOT EXISTS (SELECT 1 FROM dbo.MealSuggestions m WHERE m.Title = v.Title);
GO
