from __future__ import annotations

import unittest

from generate_sql import render_workouts
from scrape import parse_workout_detail


def workout_html(body: str) -> str:
    return f"""
    <html><head><link rel="canonical" href="https://www.muscleandstrength.com/workouts/test" /></head>
    <body><h1>Test Workout</h1>
      <div class="field-name-body"><div class="field-items"><div class="field-item">{body}</div></div></div>
    </body></html>
    """


class WorkoutScrapeTests(unittest.TestCase):
    def test_only_exercise_bearing_sections_become_workout_days(self) -> None:
        detail = parse_workout_detail(
            workout_html(
                """
                <h2>Workout Overview</h2>
                <table><tr><th>Week</th><th>Load</th></tr><tr><td>1</td><td>Light</td></tr></table>
                <h2>Day 1 - Push</h2>
                <table><tr><th>Exercise</th><th>Sets</th><th>Reps</th></tr>
                <tr><td>Bench Press</td><td>3</td><td>8</td></tr></table>
                <h2>Sample Meal Plan</h2>
                <table><tr><th>Meal</th><th>Calories</th></tr><tr><td>Lunch</td><td>600</td></tr></table>
                <h2>Day 2 - Active Recovery</h2>
                <table><tr><th>Exercise</th><th>Sets</th><th>Reps</th></tr>
                <tr><td>Optional Crunch</td><td>2</td><td>15</td></tr></table>
                """
            ),
            "https://www.muscleandstrength.com/workouts/test",
        )

        self.assertEqual(["Day 1 - Push"], [day["title"] for day in detail["days"]])
        self.assertEqual("Bench Press", detail["days"][0]["exercise_tables"][0][0]["Exercise"])

    def test_legacy_full_width_title_rows_do_not_hide_exercises(self) -> None:
        detail = parse_workout_detail(
            workout_html(
                """
                <h4>Legs Workout B</h4>
                <table><tr><th colspan="4">Legs Workout B</th></tr>
                <tr><td colspan="4">Quads, Hamstrings &amp; Calves</td></tr>
                <tr><td><strong>Exercise</strong></td><td><strong>Sets</strong></td>
                <td><strong>Reps</strong></td><td><strong>Rest</strong></td></tr>
                <tr><td>Front Squat</td><td>5</td><td>15</td><td>90 sec</td></tr></table>
                """
            ),
            "https://www.muscleandstrength.com/workouts/test",
        )

        self.assertEqual("Front Squat", detail["days"][0]["exercise_tables"][0][0]["Exercise"])


class WorkoutSqlTests(unittest.TestCase):
    def test_import_is_one_based_replaces_children_and_preserves_custom_splits(self) -> None:
        sql = "\n".join(
            render_workouts(
                [
                    {
                        "title": "Test Workout",
                        "url": "https://www.muscleandstrength.com/workouts/test",
                        "days_per_week": "1",
                        "days": [
                            {
                                "title": "Training Day A",
                                "exercise_tables": [[{"Exercise": "Squat", "Sets": "3", "Reps": "8"}]],
                                "is_rest_day": False,
                            },
                            {
                                "title": "Training Day B",
                                "exercise_tables": [[{"Exercise": "Deadlift", "Sets": "3", "Reps": "5"}]],
                                "is_rest_day": False,
                            },
                        ],
                    }
                ]
            )
        )

        self.assertIn("DayIndex=1", sql)
        self.assertIn("DayIndex=2", sql)
        self.assertNotIn("DayIndex=0", sql)
        self.assertIn("DELETE FROM dbo.SplitDayExercises WHERE SplitDayId=@ImportedDayId", sql)
        self.assertIn("(DayIndex<1 OR DayIndex>2)", sql)
        self.assertIn("DurationDays=2", sql)
        self.assertIn("DaysPerWeek=1", sql)
        self.assertIn("WHERE (SourceUrl LIKE", sql)
        self.assertNotIn("WHERE SourceUrl IS NULL OR", sql)


if __name__ == "__main__":
    unittest.main()
