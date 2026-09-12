USE SilenDb;
GO

-- Idempotent seed for the Nutrition screen's "Suggested this month" strip.
-- One flagship meal per calendar month (SuggestedMonth 1-12), each built
-- from real whole-food ingredients at realistic portions; every macro
-- figure below is summed from per-100g values sourced from USDA
-- FoodData Central (fdc.nal.usda.gov) at seed-authoring time, not fetched
-- live - same "no external runtime dependency" convention this app already
-- follows for AI analytics (see MealPlanningService/SplitService). Safe to
-- re-run.
INSERT INTO dbo.MealSuggestions
    (Title, MealType, Description, CaloriesKcal, ProteinG, CarbsG, FatsG, SuggestedMonth, IsSystemDefault, SortOrder)
SELECT v.Title, v.MealType, v.Description, v.CaloriesKcal, v.ProteinG, v.CarbsG, v.FatsG, v.SuggestedMonth, 1, v.SortOrder
FROM (VALUES
    -- Beef chuck 120g + pearl barley (cooked) 150g + carrots 80g + onion 50g
    (N'Hearty Beef & Barley Stew', N'Dinner', N'Slow-braised beef chuck with barley, carrots, and onion - a warming January dinner.', 533, 36, 53, 19, 1, 1),
    -- Salmon fillet 150g + sweet potato 200g + asparagus 100g
    (N'Baked Salmon with Sweet Potato', N'Dinner', N'Oven-baked salmon over roasted sweet potato with asparagus.', 514, 36, 46, 20, 2, 2),
    -- Chicken breast 150g + wild rice (cooked) 150g + spinach 60g + olive oil 5g
    (N'Chicken & Wild Rice Bowl', N'Lunch', N'Grilled chicken breast over wild rice and wilted spinach, light olive oil drizzle.', 457, 54, 34, 11, 3, 3),
    -- Eggs 150g (3 large) + asparagus 80g + feta 30g
    (N'Spring Veggie Frittata', N'Breakfast', N'Baked egg frittata with asparagus and feta - a spring-vegetable breakfast.', 329, 26, 6, 23, 4, 4),
    -- Chicken breast 130g + romaine 100g + parmesan 20g + caesar dressing 15g
    (N'Grilled Chicken Caesar Salad', N'Lunch', N'Grilled chicken over romaine with shaved parmesan and a light Caesar dressing.', 393, 49, 5, 19, 5, 5),
    -- Shrimp 150g + zucchini noodles 200g + olive oil 15g
    (N'Shrimp & Zucchini Noodles', N'Dinner', N'Seared shrimp over spiralized zucchini noodles in olive oil and garlic - a light summer dinner.', 315, 38, 7, 16, 6, 6),
    -- Quinoa (cooked) 150g + chickpeas 100g + cucumber 80g + feta 30g + olive oil 10g
    (N'Mediterranean Quinoa Salad', N'Lunch', N'Quinoa, chickpeas, cucumber, and feta tossed in olive oil - a make-ahead summer lunch.', 524, 20, 63, 22, 7, 7),
    -- Greek yogurt 200g + blueberries 100g + granola 30g
    (N'Greek Yogurt Berry Bowl', N'Breakfast', N'Plain Greek yogurt layered with blueberries and granola.', 316, 24, 41, 7, 8, 8),
    -- Ground turkey (93% lean) 150g + kidney beans 120g + diced tomatoes 150g
    (N'Turkey Chili', N'Dinner', N'Lean ground turkey simmered with kidney beans and tomatoes - a cozy back-to-school dinner.', 464, 49, 36, 13, 9, 9),
    -- Chicken thigh (skinless) 150g + butternut squash 200g + brussels sprouts 100g + olive oil 5g
    (N'Roasted Chicken with Butternut Squash', N'Dinner', N'Roasted chicken thigh with butternut squash and brussels sprouts - a fall harvest dinner.', 481, 44, 30, 22, 10, 10),
    -- Turkey breast (skinless) 150g + mashed potato 200g + green beans 80g
    (N'Herb-Roasted Turkey Breast with Mashed Potatoes', N'Dinner', N'Herb-roasted turkey breast with mashed potatoes and green beans.', 457, 51, 40, 10, 11, 11),
    -- Cod fillet 150g + parsnip mash 150g (+5g butter) + kale 60g
    (N'Baked Cod with Root Vegetable Mash', N'Dinner', N'Baked cod over parsnip mash with sauteed kale - a light dish to close out the year.', 317, 38, 29, 6, 12, 12)
) AS v(Title, MealType, Description, CaloriesKcal, ProteinG, CarbsG, FatsG, SuggestedMonth, SortOrder)
WHERE NOT EXISTS (SELECT 1 FROM dbo.MealSuggestions m WHERE m.Title = v.Title);
GO
