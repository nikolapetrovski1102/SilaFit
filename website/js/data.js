/* ============================================================
   SilaFit data store — shared by the marketing site and the
   admin dashboard.

   Seed content mirrors the real database seeds
   (database/seed/001_SeedReferenceData.sql and
   003_SeedMealSuggestions.sql). Admin edits persist to
   localStorage under one versioned key; the marketing pages read
   the same store, so changes made in the dashboard are live on
   the landing page immediately. Swap the internals for real API
   calls (Silen.Api) when wiring the backend.
   ============================================================ */
(function (global) {
  'use strict';

  var STORAGE_KEY = 'silafit.store.v1';

  var MONTHS = ['January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'];

  var MEAL_TYPES = ['Breakfast', 'Lunch', 'Dinner', 'Snack'];

  /* ---------------- Seed data (mirrors SQL seeds) ---------------- */

  var SEED_SUGGESTIONS = [
    { title: 'Hearty Beef & Barley Stew', mealType: 'Dinner', description: 'Slow-braised beef chuck with barley, carrots, and onion - a warming January dinner.', caloriesKcal: 533, proteinG: 36, carbsG: 53, fatsG: 19, month: 1 },
    { title: 'Baked Salmon with Sweet Potato', mealType: 'Dinner', description: 'Oven-baked salmon over roasted sweet potato with asparagus.', caloriesKcal: 514, proteinG: 36, carbsG: 46, fatsG: 20, month: 2 },
    { title: 'Chicken & Wild Rice Bowl', mealType: 'Lunch', description: 'Grilled chicken breast over wild rice and wilted spinach, light olive oil drizzle.', caloriesKcal: 457, proteinG: 54, carbsG: 34, fatsG: 11, month: 3 },
    { title: 'Spring Veggie Frittata', mealType: 'Breakfast', description: 'Baked egg frittata with asparagus and feta - a spring-vegetable breakfast.', caloriesKcal: 329, proteinG: 26, carbsG: 6, fatsG: 23, month: 4 },
    { title: 'Grilled Chicken Caesar Salad', mealType: 'Lunch', description: 'Grilled chicken over romaine with shaved parmesan and a light Caesar dressing.', caloriesKcal: 393, proteinG: 49, carbsG: 5, fatsG: 19, month: 5 },
    { title: 'Shrimp & Zucchini Noodles', mealType: 'Dinner', description: 'Seared shrimp over spiralized zucchini noodles in olive oil and garlic - a light summer dinner.', caloriesKcal: 315, proteinG: 38, carbsG: 7, fatsG: 16, month: 6 },
    { title: 'Mediterranean Quinoa Salad', mealType: 'Lunch', description: 'Quinoa, chickpeas, cucumber, and feta tossed in olive oil - a make-ahead summer lunch.', caloriesKcal: 524, proteinG: 20, carbsG: 63, fatsG: 22, month: 7 },
    { title: 'Greek Yogurt Berry Bowl', mealType: 'Breakfast', description: 'Plain Greek yogurt layered with blueberries and granola.', caloriesKcal: 316, proteinG: 24, carbsG: 41, fatsG: 7, month: 8 },
    { title: 'Turkey Chili', mealType: 'Dinner', description: 'Lean ground turkey simmered with kidney beans and tomatoes - a cozy back-to-school dinner.', caloriesKcal: 464, proteinG: 49, carbsG: 36, fatsG: 13, month: 9 },
    { title: 'Roasted Chicken with Butternut Squash', mealType: 'Dinner', description: 'Roasted chicken thigh with butternut squash and brussels sprouts - a fall harvest dinner.', caloriesKcal: 481, proteinG: 44, carbsG: 30, fatsG: 22, month: 10 },
    { title: 'Herb-Roasted Turkey Breast with Mashed Potatoes', mealType: 'Dinner', description: 'Herb-roasted turkey breast with mashed potatoes and green beans.', caloriesKcal: 457, proteinG: 51, carbsG: 40, fatsG: 10, month: 11 },
    { title: 'Baked Cod with Root Vegetable Mash', mealType: 'Dinner', description: 'Baked cod over parsnip mash with sauteed kale - a light dish to close out the year.', caloriesKcal: 317, proteinG: 38, carbsG: 29, fatsG: 6, month: 12 }
  ];

  var SEED_EXERCISES = [
    ['Incline Dumbbell Bench Press', 'chest', 'Dumbbell', 1],
    ['Seated Dumbbell Overhead Press', 'shoulders', 'Dumbbell', 1],
    ['Cable Standing Flyes', 'chest', 'Cable', 0],
    ['Barbell Conventional Deadlift', 'back', 'Barbell', 1],
    ['Wide-Grip Lat Pulldown', 'back', 'Cable', 1],
    ['Incline Dumbbell Hammer Curl', 'arms', 'Dumbbell', 0],
    ['Barbell High-Bar Back Squat', 'legs', 'Barbell', 1],
    ['Romanian Deadlift (Dumbbells)', 'legs', 'Dumbbell', 1],
    ['Seated Leg Extension', 'legs', 'Machine', 0],
    ['Incline Barbell Bench Press', 'chest', 'Barbell', 1],
    ['Chest-Supported T-Bar Row', 'back', 'Barbell', 1],
    ['Bulgarian Split Squat', 'legs', 'Dumbbell', 0],
    ['Cable Lateral Raise', 'shoulders', 'Cable', 0],
    ['Overhead Rope Extension', 'arms', 'Cable', 0],
    ['Barbell Hip Thrust', 'legs', 'Barbell', 1],
    ['Push-Up', 'chest', 'Bodyweight', 1],
    ['Pull-Up', 'back', 'Bodyweight', 1],
    ['Bodyweight Dip', 'arms', 'Bodyweight', 1],
    ['Plank Hold', 'core', 'Bodyweight', 0],
    ['Kettlebell Swing', 'legs', 'Kettlebell', 1]
  ].map(function (e) {
    return { name: e[0], muscleGroup: e[1], equipment: e[2], isCompound: !!e[3] };
  });

  var SEED_PLANS = [
    {
      code: 'FREE', name: 'Free Tier',
      tagline: 'Essential hardware tracking and routine logging for self-guided lifters.',
      monthlyPrice: 0, yearlyPrice: 0, isFeatured: false,
      features: [
        { text: 'Workout split library & session logging', highlighted: false },
        { text: 'Hydration & bodyweight tracking', highlighted: false },
        { text: 'Basic streak & progress stats', highlighted: false },
        { text: 'Monthly meal suggestions', highlighted: false }
      ]
    },
    {
      code: 'PRO', name: 'Pro Tier',
      tagline: 'Advanced volume telemetry, predictive PR curves, and automated deload signals.',
      monthlyPrice: 2.49, yearlyPrice: 20.99, isFeatured: true,
      features: [
        { text: 'Everything included in Free tier', highlighted: false },
        { text: 'AI-powered monthly analytics report', highlighted: true },
        { text: 'Advanced 1RM progression & PR prediction', highlighted: false },
        { text: 'Intelligent recovery & deload detection', highlighted: false },
        { text: 'Custom split builder with infinite routines', highlighted: false }
      ]
    },
    {
      code: 'ADVANCED', name: 'Advanced Tier',
      tagline: 'Weekly AI check-ins, on-demand AI-generated plans, and unlimited splits & diet plans.',
      monthlyPrice: 4.99, yearlyPrice: 41.99, isFeatured: false,
      features: [
        { text: 'Everything included in Pro tier', highlighted: false },
        { text: 'Adaptive meal planner calibrated to load', highlighted: true },
        { text: 'Weekly AI check-ins with prioritized recommendations', highlighted: false },
        { text: 'AI-generated workout splits & diet plans on request', highlighted: false },
        { text: 'Unlimited saved splits & diet plans', highlighted: false }
      ]
    }
  ];

  /* Weekly meal plan templates — the admin dashboard's flagship editor.
     days: 7 entries (Mon..Sun), each holding per-meal-type slots. */
  function meal(type, title, kcal, p, c, f) {
    return { type: type, title: title, caloriesKcal: kcal, proteinG: p, carbsG: c, fatsG: f };
  }
  function day(name, meals) { return { day: name, meals: meals }; }

  var SEED_MEAL_PLANS = [
    {
      name: 'Lean Cut — 2000 kcal',
      goal: 'LoseFat',
      description: 'High-protein deficit week built from whole foods. Calorie-controlled without feeling like a diet.',
      targets: { calories: 2000, proteinG: 160, carbsG: 180, fatsG: 65 },
      isPublished: true,
      days: [
        day('Monday', [
          meal('Breakfast', 'Greek Yogurt Berry Bowl', 316, 24, 41, 7),
          meal('Lunch', 'Grilled Chicken Caesar Salad', 393, 49, 5, 19),
          meal('Dinner', 'Shrimp & Zucchini Noodles', 315, 38, 7, 16),
          meal('Snack', 'Apple & Almond Butter', 195, 4, 27, 9)
        ]),
        day('Tuesday', [
          meal('Breakfast', 'Spring Veggie Frittata', 329, 26, 6, 23),
          meal('Lunch', 'Mediterranean Quinoa Salad', 524, 20, 63, 22),
          meal('Dinner', 'Baked Cod with Root Vegetable Mash', 317, 38, 29, 6),
          meal('Snack', 'Cottage Cheese & Cucumber', 150, 18, 6, 5)
        ]),
        day('Wednesday', [
          meal('Breakfast', 'Protein Oats with Banana', 380, 28, 52, 8),
          meal('Lunch', 'Chicken & Wild Rice Bowl', 457, 54, 34, 11),
          meal('Dinner', 'Baked Salmon with Sweet Potato', 514, 36, 46, 20),
          meal('Snack', 'Boiled Eggs (2) & Cherry Tomatoes', 160, 13, 4, 10)
        ]),
        day('Thursday', [
          meal('Breakfast', 'Greek Yogurt Berry Bowl', 316, 24, 41, 7),
          meal('Lunch', 'Turkey Chili', 464, 49, 36, 13),
          meal('Dinner', 'Shrimp & Zucchini Noodles', 315, 38, 7, 16),
          meal('Snack', 'Protein Shake', 160, 30, 6, 2)
        ]),
        day('Friday', [
          meal('Breakfast', 'Spring Veggie Frittata', 329, 26, 6, 23),
          meal('Lunch', 'Grilled Chicken Caesar Salad', 393, 49, 5, 19),
          meal('Dinner', 'Baked Cod with Root Vegetable Mash', 317, 38, 29, 6),
          meal('Snack', 'Apple & Almond Butter', 195, 4, 27, 9)
        ]),
        day('Saturday', [
          meal('Breakfast', 'Protein Oats with Banana', 380, 28, 52, 8),
          meal('Lunch', 'Mediterranean Quinoa Salad', 524, 20, 63, 22),
          meal('Dinner', 'Baked Salmon with Sweet Potato', 514, 36, 46, 20),
          meal('Snack', 'Cottage Cheese & Cucumber', 150, 18, 6, 5)
        ]),
        day('Sunday', [
          meal('Breakfast', 'Greek Yogurt Berry Bowl', 316, 24, 41, 7),
          meal('Lunch', 'Chicken & Wild Rice Bowl', 457, 54, 34, 11),
          meal('Dinner', 'Roasted Chicken with Butternut Squash', 481, 44, 30, 22),
          meal('Snack', 'Protein Shake', 160, 30, 6, 2)
        ])
      ]
    },
    {
      name: 'Muscle Builder — 3000 kcal',
      goal: 'BuildMuscle',
      description: 'Surplus week for hypertrophy blocks. Calorie-dense whole foods front-loaded around training.',
      targets: { calories: 3000, proteinG: 210, carbsG: 340, fatsG: 90 },
      isPublished: true,
      days: [
        day('Monday', [
          meal('Breakfast', 'Protein Oats with Peanut Butter', 620, 35, 70, 24),
          meal('Lunch', 'Hearty Beef & Barley Stew', 533, 36, 53, 19),
          meal('Dinner', 'Herb-Roasted Turkey Breast with Mashed Potatoes', 457, 51, 40, 10),
          meal('Snack', 'Mass Shake & Banana', 480, 42, 58, 8)
        ]),
        day('Tuesday', [
          meal('Breakfast', 'Spring Veggie Frittata + Toast', 480, 30, 30, 28),
          meal('Lunch', 'Chicken & Wild Rice Bowl (double)', 700, 78, 52, 17),
          meal('Dinner', 'Baked Salmon with Sweet Potato', 514, 36, 46, 20),
          meal('Snack', 'Greek Yogurt & Granola', 420, 28, 52, 12)
        ]),
        day('Wednesday', [
          meal('Breakfast', 'Protein Oats with Banana', 380, 28, 52, 8),
          meal('Lunch', 'Turkey Chili + Rice', 640, 55, 70, 15),
          meal('Dinner', 'Roasted Chicken with Butternut Squash', 481, 44, 30, 22),
          meal('Snack', 'Mass Shake', 420, 40, 50, 7)
        ]),
        day('Thursday', [
          meal('Breakfast', 'Greek Yogurt Berry Bowl + Toast', 470, 28, 65, 10),
          meal('Lunch', 'Hearty Beef & Barley Stew', 533, 36, 53, 19),
          meal('Dinner', 'Herb-Roasted Turkey Breast with Mashed Potatoes', 457, 51, 40, 10),
          meal('Snack', 'Cottage Cheese & Fruit', 300, 30, 28, 6)
        ]),
        day('Friday', [
          meal('Breakfast', 'Protein Oats with Peanut Butter', 620, 35, 70, 24),
          meal('Lunch', 'Grilled Chicken Caesar Salad + Potatoes', 560, 55, 38, 22),
          meal('Dinner', 'Baked Salmon with Sweet Potato', 514, 36, 46, 20),
          meal('Snack', 'Mass Shake & Banana', 480, 42, 58, 8)
        ]),
        day('Saturday', [
          meal('Breakfast', 'Pancakes & Eggs', 680, 32, 80, 26),
          meal('Lunch', 'Turkey Chili + Rice', 640, 55, 70, 15),
          meal('Dinner', 'Roasted Chicken with Butternut Squash', 481, 44, 30, 22),
          meal('Snack', 'Greek Yogurt & Granola', 420, 28, 52, 12)
        ]),
        day('Sunday', [
          meal('Breakfast', 'Spring Veggie Frittata + Toast', 480, 30, 30, 28),
          meal('Lunch', 'Hearty Beef & Barley Stew', 533, 36, 53, 19),
          meal('Dinner', 'Baked Cod with Root Vegetable Mash + Rice', 480, 42, 55, 9),
          meal('Snack', 'Mass Shake', 420, 40, 50, 7)
        ])
      ]
    },
    {
      name: 'Stay Active — 2300 kcal',
      goal: 'MaintainActive',
      description: 'Balanced maintenance week for general health and consistent energy.',
      targets: { calories: 2300, proteinG: 140, carbsG: 260, fatsG: 75 },
      isPublished: false,
      days: [
        day('Monday', [
          meal('Breakfast', 'Greek Yogurt Berry Bowl', 316, 24, 41, 7),
          meal('Lunch', 'Mediterranean Quinoa Salad', 524, 20, 63, 22),
          meal('Dinner', 'Roasted Chicken with Butternut Squash', 481, 44, 30, 22),
          meal('Snack', 'Apple & Almond Butter', 195, 4, 27, 9)
        ]),
        day('Tuesday', [
          meal('Breakfast', 'Protein Oats with Banana', 380, 28, 52, 8),
          meal('Lunch', 'Grilled Chicken Caesar Salad', 393, 49, 5, 19),
          meal('Dinner', 'Turkey Chili', 464, 49, 36, 13),
          meal('Snack', 'Boiled Eggs (2)', 140, 12, 1, 10)
        ]),
        day('Wednesday', [
          meal('Breakfast', 'Spring Veggie Frittata', 329, 26, 6, 23),
          meal('Lunch', 'Chicken & Wild Rice Bowl', 457, 54, 34, 11),
          meal('Dinner', 'Baked Cod with Root Vegetable Mash', 317, 38, 29, 6),
          meal('Snack', 'Cottage Cheese & Cucumber', 150, 18, 6, 5)
        ]),
        day('Thursday', [
          meal('Breakfast', 'Greek Yogurt Berry Bowl', 316, 24, 41, 7),
          meal('Lunch', 'Hearty Beef & Barley Stew', 533, 36, 53, 19),
          meal('Dinner', 'Shrimp & Zucchini Noodles', 315, 38, 7, 16),
          meal('Snack', 'Protein Shake', 160, 30, 6, 2)
        ]),
        day('Friday', [
          meal('Breakfast', 'Protein Oats with Banana', 380, 28, 52, 8),
          meal('Lunch', 'Mediterranean Quinoa Salad', 524, 20, 63, 22),
          meal('Dinner', 'Baked Salmon with Sweet Potato', 514, 36, 46, 20),
          meal('Snack', 'Apple & Almond Butter', 195, 4, 27, 9)
        ]),
        day('Saturday', [
          meal('Breakfast', 'Pancakes & Eggs', 680, 32, 80, 26),
          meal('Lunch', 'Grilled Chicken Caesar Salad', 393, 49, 5, 19),
          meal('Dinner', 'Herb-Roasted Turkey Breast with Mashed Potatoes', 457, 51, 40, 10),
          meal('Snack', 'Greek Yogurt & Granola', 420, 28, 52, 12)
        ]),
        day('Sunday', [
          meal('Breakfast', 'Spring Veggie Frittata', 329, 26, 6, 23),
          meal('Lunch', 'Chicken & Wild Rice Bowl', 457, 54, 34, 11),
          meal('Dinner', 'Turkey Chili', 464, 49, 36, 13),
          meal('Snack', 'Boiled Eggs (2)', 140, 12, 1, 10)
        ])
      ]
    }
  ];

  var SEED_USERS = [
    { name: 'Elena Ristova', email: 'elena.r@example.com', plan: 'PRO', streak: 34, joined: '2025-11-02', status: 'Active' },
    { name: 'Marko Petrov', email: 'marko.p@example.com', plan: 'ADVANCED', streak: 112, joined: '2025-06-18', status: 'Active' },
    { name: 'Ivana Kotevska', email: 'ivana.k@example.com', plan: 'FREE', streak: 7, joined: '2026-08-21', status: 'Active' },
    { name: 'Stefan Dimitrov', email: 'stefan.d@example.com', plan: 'PRO', streak: 58, joined: '2025-09-30', status: 'Active' },
    { name: 'Ana Georgieva', email: 'ana.g@example.com', plan: 'FREE', streak: 0, joined: '2026-09-04', status: 'Churned' },
    { name: 'Viktor Stojanov', email: 'viktor.s@example.com', plan: 'ADVANCED', streak: 201, joined: '2025-02-14', status: 'Active' },
    { name: 'Milica Trajkova', email: 'milica.t@example.com', plan: 'PRO', streak: 19, joined: '2026-04-11', status: 'Active' },
    { name: 'Goran Nikolov', email: 'goran.n@example.com', plan: 'FREE', streak: 3, joined: '2026-08-29', status: 'Active' }
  ];

  /* ---------------- Store ---------------- */

  function uid() {
    return 'id-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 8);
  }

  function seedState() {
    function withIds(list) {
      return list.map(function (item) {
        var copy = JSON.parse(JSON.stringify(item));
        copy.id = uid();
        return copy;
      });
    }
    return {
      mealSuggestions: withIds(SEED_SUGGESTIONS),
      exercises: withIds(SEED_EXERCISES),
      plans: withIds(SEED_PLANS),
      mealPlans: withIds(SEED_MEAL_PLANS),
      users: withIds(SEED_USERS)
    };
  }

  function load() {
    try {
      var raw = global.localStorage.getItem(STORAGE_KEY);
      if (raw) {
        var parsed = JSON.parse(raw);
        if (parsed && parsed.mealSuggestions && parsed.plans && parsed.mealPlans) return parsed;
      }
    } catch (e) { /* corrupted -> reseed */ }
    var fresh = seedState();
    save(fresh);
    return fresh;
  }

  function save(state) {
    try { global.localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); } catch (e) { /* private mode */ }
  }

  var state = load();

  function persist() { save(state); }

  /* Generic collection helpers */
  function collection(name) {
    return {
      all: function () { return state[name].slice(); },
      get: function (id) {
        return state[name].find(function (x) { return x.id === id; }) || null;
      },
      create: function (item) {
        item.id = uid();
        state[name].push(item);
        persist();
        return item;
      },
      update: function (id, patch) {
        var item = this.get(id);
        if (!item) return null;
        Object.keys(patch).forEach(function (k) { item[k] = patch[k]; });
        persist();
        return item;
      },
      remove: function (id) {
        state[name] = state[name].filter(function (x) { return x.id !== id; });
        persist();
      }
    };
  }

  global.SilaStore = {
    MONTHS: MONTHS,
    MEAL_TYPES: MEAL_TYPES,
    GOALS: ['LoseFat', 'BuildMuscle', 'MaintainActive'],
    GOAL_LABELS: { LoseFat: 'Lose Fat', BuildMuscle: 'Build Muscle', MaintainActive: 'Stay Active' },

    mealSuggestions: collection('mealSuggestions'),
    exercises: collection('exercises'),
    plans: collection('plans'),
    mealPlans: collection('mealPlans'),
    users: collection('users'),

    suggestionsForMonth: function (monthIndex1to12) {
      return state.mealSuggestions.filter(function (s) { return s.month === monthIndex1to12; });
    },
    featuredPlan: function () {
      return state.plans.find(function (p) { return p.isFeatured; }) || null;
    },

    resetToSeed: function () {
      state = seedState();
      persist();
    },

    _uid: uid
  };
})(window);
