import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silafit/core/api/api_client.dart';
import 'package:silafit/core/session/session_store.dart';
import 'package:silafit/features/meals/meal_controller.dart';
import 'package:silafit/features/meals/meal_models.dart';
import 'package:silafit/features/meals/meal_repository.dart';
import 'package:silafit/features/meals/meal_tracker_screen.dart';
import 'package:silafit/features/meals/widgets/macro_amount_row.dart';

class _FakeMeals extends MealRepository {
  _FakeMeals() : super(ApiClient(sessionStore: SessionStore()));

  final searches = <String>[];
  Map<String, Object?>? created;

  @override
  Future<List<FoodItem>> searchFoods(String query, {int take = 25}) async {
    searches.add(query);
    return const [
      FoodItem(
        foodNutritionId: 7,
        name: 'Chicken breast',
        caloriesKcal: 165,
        proteinG: 31,
        carbohydrateG: 0,
        fatG: 3.6,
      ),
    ];
  }

  @override
  Future<MealDay> getDay(DateTime date) async => throw Exception('offline');

  @override
  Future<MealLog> createLog({
    required DateTime logDate,
    required String mealType,
    required String title,
    required int caloriesKcal,
    required int proteinG,
    required int carbsG,
    required int fatsG,
    String status = 'Planned',
    List<MealLogItem>? items,
  }) async {
    created = {
      'mealType': mealType,
      'title': title,
      'kcal': caloriesKcal,
      'items': items,
    };
    return MealLog(
      mealLogId: 'm1',
      logDateUtc: logDate.toIso8601String(),
      mealType: mealType,
      title: title,
      caloriesKcal: caloriesKcal,
      proteinG: proteinG,
      carbsG: carbsG,
      fatsG: fatsG,
      status: status,
      items: items ?? const [],
    );
  }
}

String? _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller?.text;

void main() {
  const chicken = FoodItem(
    foodNutritionId: 1,
    name: 'Chicken breast',
    caloriesKcal: 165,
    proteinG: 31,
    carbohydrateG: 0,
    fatG: 3.6,
    sodiumMg: 74,
  );
  const rice = FoodItem(
    foodNutritionId: 2,
    name: 'White rice, cooked',
    caloriesKcal: 130,
    proteinG: 2.7,
    carbohydrateG: 28,
    fatG: 0.3,
    fiberG: 0.4,
  );

  test('a food scales from per-100 g to the grams eaten', () {
    final item = MealLogItem.fromFood(chicken, 150);
    expect(item.caloriesKcal, closeTo(247.5, 0.001));
    expect(item.proteinG, closeTo(46.5, 0.001));
    expect(item.sodiumMg, closeTo(111, 0.001));
    expect(item.fiberG, isNull);
  });

  test('re-weighing a stored item rescales proportionally', () {
    final stored = MealLogItem.fromJson(
        MealLogItem.fromFood(rice, 200).toJson());
    final half = stored.withGrams(100);
    expect(half.caloriesKcal, closeTo(130, 0.001));
    expect(half.carbsG, closeTo(28, 0.001));
  });

  test('meal totals sum every food and keep optional nutrients optional', () {
    final totals = MealTotals.of([
      MealLogItem.fromFood(chicken, 100),
      MealLogItem.fromFood(rice, 100),
    ]);
    expect(totals.caloriesKcal, closeTo(295, 0.001));
    expect(totals.proteinG, closeTo(33.7, 0.001));
    expect(totals.fiberG, closeTo(0.4, 0.001));
    expect(totals.sugarG, isNull);
  });

  testWidgets('the macro type selector only appears once a number is typed',
      (tester) async {
    final entry = MacroEntry();
    addTearDown(entry.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => MacroAmountRow(
            entry: entry,
            taken: const {},
            onChanged: () => setState(() {}),
          ),
        ),
      ),
    ));

    expect(find.text('Protein'), findsNothing);

    await tester.enterText(find.byType(TextField), '30');
    await tester.pumpAndSettle();
    expect(find.text('Protein'), findsOneWidget);

    await tester.tap(find.text('Protein'));
    await tester.pumpAndSettle();
    expect(entry.kind, MacroKind.protein);
    expect(entry.value, 30);
  });

  testWidgets('name lifts into the title, then foods are searched and added',
      (tester) async {
    final repo = _FakeMeals();
    final controller = MealController(repo);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: const Scaffold(),
    ));
    navigator.currentState!.push(MaterialPageRoute(
        builder: (_) => MealTrackerScreen(controller: controller)));
    await tester.pumpAndSettle();

    // Step 1: one field, preset to a meal type and fully selected.
    expect(find.byType(TextField), findsOneWidget);
    expect(kMealTypes, contains(_fieldText(tester)));

    await tester.enterText(find.byType(TextField), 'Big lunch');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();

    // The name is now the title; the same field is the ingredient search,
    // and the name picked the meal type.
    expect(find.text('Big lunch'), findsOneWidget);
    expect(find.text('LUNCH'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(_fieldText(tester), isEmpty);

    await tester.enterText(find.byType(TextField), 'chick');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(repo.searches, ['chick']);

    // Tap the result - it flies into the ingredients at 100 g.
    await tester.tap(find.text('Chicken breast'));
    await tester.pumpAndSettle();
    expect(find.text('Chicken breast'), findsOneWidget);
    expect(find.text('100 g'), findsOneWidget);
    expect(find.text('165 kcal'), findsOneWidget);

    // Step up the grams; the ingredient and meal totals follow.
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('110 g'), findsOneWidget);
    expect(find.text('182 kcal'), findsOneWidget);

    await tester.tap(find.text('Save meal · 182 kcal'));
    await tester.pumpAndSettle();
    expect(repo.created?['title'], 'Big lunch');
    expect(repo.created?['mealType'], 'Lunch');
    expect(repo.created?['kcal'], 182);
    expect((repo.created?['items'] as List<MealLogItem>).single.grams, 110);
    expect(find.byType(MealTrackerScreen), findsNothing);
  });
}
