#!/usr/bin/env python3
"""Generate an idempotent SQL Server seed from the scraped M&S JSON files."""

from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_INPUT = ROOT / "data" / "scraped" / "muscleandstrength"
DEFAULT_OUTPUT = ROOT / "database" / "seed" / "006_ImportMuscleAndStrength.sql"
ALIASES_FILE = Path(__file__).resolve().parent / "exercise_aliases.csv"


def sql_text(value: Any, limit: int | None = None) -> str:
    if value is None:
        return "NULL"
    text = str(value)
    if limit is not None:
        text = text[:limit]
    return "N'" + text.replace("'", "''") + "'"


def sql_json(value: Any) -> str:
    return sql_text(json.dumps(value, ensure_ascii=False, separators=(",", ":")))


def first_number(value: Any, default: int = 0) -> int:
    match = re.search(r"\d+(?:\.\d+)?", str(value or ""))
    return round(float(match.group(0))) if match else default


def rep_range(value: Any) -> tuple[int, int]:
    values = [round(float(x)) for x in re.findall(r"\d+(?:\.\d+)?", str(value or ""))]
    if not values:
        return 1, 1
    return max(1, min(values)), min(255, max(values))


def workout_category(item: dict[str, Any]) -> str:
    title = (item.get("title") or "").lower()
    summary = (item.get("summary") or "").lower()
    workout_type = (item.get("workout_type") or "").lower()
    categories = " ".join(item.get("source_categories") or []).lower()
    combined = " ".join((title, summary, workout_type, categories))
    if "p.h.u.l" in title or "phul" in title:
        return "PHUL"
    if "phat" in combined:
        return "PHAT"
    if "arnold" in combined:
        return "ArnoldSplit"
    if "push pull legs" in combined or "push/pull/legs" in combined or "ppl" in title:
        return "PushPullLegs"
    if "upper/lower" in combined or "upper lower" in combined:
        return "UpperLower"
    if "powerlifting" in combined or "strength" in workout_type:
        return "Powerlifting"
    if "bodyweight" in combined or "body only" in (item.get("equipment_required") or "").lower():
        return "Calisthenics"
    if "circuit" in combined or "cardio" in categories:
        return "Circuit"
    if "glute" in combined:
        return "GluteFocus"
    if "full body" in combined:
        return "FullBody"
    return "BroSplit"


def workout_goal(item: dict[str, Any]) -> str:
    goal = (item.get("main_goal") or "").lower()
    categories = " ".join(item.get("source_categories") or []).lower()
    if "fat" in goal or "fat loss" in categories:
        return "LoseFat"
    if any(value in goal for value in ("build muscle", "increase strength", "powerlifting")) or "muscle building" in categories:
        return "BuildMuscle"
    return "MaintainActive"


def bounded_number(value: Any, low: int, high: int, default: int | None = None) -> int | None:
    values = re.findall(r"\d+", str(value or ""))
    if not values:
        return default
    return max(low, min(high, int(values[0])))


def minute_range(value: Any) -> tuple[int | None, int | None]:
    values = [max(1, min(600, int(x))) for x in re.findall(r"\d+", str(value or ""))]
    if not values:
        return None, None
    return min(values), max(values)


def exercise_value(row: dict[str, Any], wanted: str) -> str | None:
    for key, value in row.items():
        if wanted.lower() in key.lower():
            return str(value) if value is not None else None
    return None


# Muscle & Strength numbers the exercise column inside a day's table ("1. Squat",
# "4b. Cable Curl"), and marks superset pairings with a letter+digit label
# ("A1."/"A2." are performed back to back, then "B1."/"B2.", and so on). The
# ordering is already captured by SortOrder, so the prefix is noise that would otherwise create
# a second Exercises row for an exercise that already exists under its plain name
# ("Goblet Squat" vs "A1. Goblet Squat"), fragmenting exercise matching.
LEADING_ORDINAL = re.compile(r"^\s*[A-Za-z]?\d+[a-z]?\.\s*")


# Hand-reviewed spelling variants of one exercise ("Pull Ups", "Pull-Up", "Pull Ups *")
# mapped to the single row the catalogue keeps. Deliberately an explicit list, not
# fuzzy matching: "- Power/- Muscle/- Burn" phase blocks and "(Use 20% less weight…)"
# back-off sets sit next to their base exercise on the same day, so they are
# different prescriptions and never appear here. Keys are matched case-insensitively,
# like the database's Name lookups.
def load_exercise_aliases(path: Path = ALIASES_FILE) -> dict[str, str]:
    if not path.exists():
        return {}
    with path.open(encoding="utf-8", newline="") as handle:
        return {row["variant"].casefold(): row["canonical"] for row in csv.DictReader(handle)}


EXERCISE_ALIASES = load_exercise_aliases()


def normalize_exercise_name(name: str | None) -> str | None:
    if not name:
        return name
    stripped = LEADING_ORDINAL.sub("", name).strip()
    if not stripped:
        return None
    return EXERCISE_ALIASES.get(stripped.casefold(), stripped)


def workout_rows(item: dict[str, Any]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for day in item.get("days") or []:
        for table in day.get("exercise_tables") or []:
            if isinstance(table, list):
                rows.extend(row for row in table if isinstance(row, dict) and exercise_value(row, "Exercise"))
    return rows


def workout_exercise_names(items: list[dict[str, Any]]) -> list[str]:
    names: set[str] = set()
    for item in items:
        for row in workout_rows(item):
            name = normalize_exercise_name(exercise_value(row, "Exercise"))
            if name:
                names.add(name)
    return sorted(names, key=str.casefold)


# Combos, circuits, cardio and mobility entries: no single primary muscle, so the
# specific rules below are skipped and the broad keyword fallback decides.
MUSCLE_GROUP_SKIP = re.compile(
    r"superset|\bcircuit\b|\bto (arnold|shoulder|press)\b|/curl/|\bor\b.*\b(deadlift|curl|press)\b"
    r"|cardio|interval|sprint|jog\b|run\b|treadmill|walk\b|stair|jump rope|burpee|tabata|skips"
    r"|rowing machine|rest day|stretch|foam roll|flow\b|lacrosse|mobilization|recovery|jab|cross\b"
    r"|crosses|hook|roundhouse|boxing|figure 8|8 counts|cool down|warm[\s-]?up"
)

# Ordered most-specific first; the first match wins. Order matters: "leg curl" is legs
# before the arms "curl" rule, "chest supported row" is back before the chest rule,
# "close-grip bench press" is arms before the chest "bench press" rule.
MUSCLE_GROUP_RULES = [
    ("core", r"plank|sit[\s-]?ups?\b|crunch|leg raise|knee raise|leg lift|toe touch|heel touch|knee[\s-]?ins?\b"
             r"|knee tuck|pike|russian twist|\bab\b|\babs\b|ab wheel|roll ?out|v[\s-]?up|flutter|hollow|dead bug"
             r"|bird dog|mountain climber|pallof|wood ?chop|cable chop|wipers|oblique|side bend|turkish get up"
             r"|air bike|bicycle"),
    ("legs", r"leg curl|hamstring curl|glute|donkey kick|fire hydrant|frog pump|clam|hip thrust|abduct|adduct"
             r"|hyperextension|pull[\s-]?through|\brdl\b|deadlift|good morning|squat|lunge|leg press|leg extension"
             r"|calf|step[\s-]?up|hack|kettlebell swing|kb swing|alternating swing|box jump|vertical jump|band walk"
             r"|sled|pistol|90/90 hip"),
    ("shoulders", r"rear delt|reverse fl(y|ies|ye)|reverse pec|face ?pull|upright row|band pull[\s-]?apart"
                  r"|lateral raise|front raise|lateral machine raise|arnold|military press|overhead press"
                  r"|shoulder press|push press|behind the neck press|\bz press|landmine (push )?press"
                  r"|seated (barbell|dumbbell|smith machine) press|standing (barbell|dumbbell) press"
                  r"|single arm dumbbell press|half kneeling press|kettlebell press|arm circles"),
    ("back", r"\brows?\b|pull[\s-]?ups?\b|chin[\s-]?ups?\b|pull ?down|lat pull|shrug|superman|\bt[\s-]bar"
             r"|back extension"),
    ("arms", r"close[\s-]?grip bench|curl|tricep|skull ?crusher|press ?down|push ?down|kick ?back|french press"
             r"|extr?ension|(?<!chest )\bdips?\b|bicep"),
    ("chest", r"bench press|\bdb bench\b|chest|\bfly|flye|push[\s-]?ups?\b|pushup|pull ?over|crossover"
              r"|floor press|pec deck|(incline|decline|flat bench|one arm|neutral grip) (bench )?dumbbell press"
              r"|(incline|decline) (bench )?press"),
]
MUSCLE_GROUP_PATTERNS = [(group, re.compile(pattern)) for group, pattern in MUSCLE_GROUP_RULES]


def muscle_group(name: str) -> str:
    n = name.lower()
    if not MUSCLE_GROUP_SKIP.search(n):
        for group, pattern in MUSCLE_GROUP_PATTERNS:
            if pattern.search(n):
                return group
    groups = [
        ("core", ("ab ", "abs", "crunch", "plank", "twist", "knee raise", "leg raise", "sit up", "sit-up")),
        ("legs", ("squat", "lunge", "leg ", "calf", "hamstring", "glute", "hip ", "deadlift", "step up", "step-up")),
        ("chest", ("bench press", "chest", "fly", "flye", "push up", "push-up", "pullover")),
        ("back", ("row", "pull up", "pull-up", "pulldown", "pull down", "chin up", "chin-up", "lat ", "back ", "shrug")),
        ("shoulders", ("shoulder", "military press", "lateral raise", "front raise", "upright row", "rear delt")),
        ("arms", ("curl", "tricep", "triceps", "dip", "skullcrusher", "wrist", "forearm")),
    ]
    for group, terms in groups:
        if any(term in n for term in terms):
            return group
    return "core"


def equipment_type(name: str) -> str | None:
    n = name.lower()
    for label, terms in [
        ("Dumbbell", ("dumbbell", "db ")),
        ("Barbell", ("barbell", "ez bar")),
        ("Cable", ("cable", "pulldown", "pull down")),
        ("Machine", ("machine", "leg press", "leg extension", "leg curl", "hack squat")),
        ("Bodyweight", ("push up", "push-up", "pull up", "pull-up", "chin up", "chin-up", "dip", "plank")),
        ("Kettlebell", ("kettlebell",)),
    ]:
        if any(term in n for term in terms):
            return label
    return None


def is_compound(name: str) -> int:
    n = name.lower()
    return int(any(term in n for term in (
        "squat", "deadlift", "bench press", "press", "row", "pull up", "pull-up",
        "chin up", "chin-up", "dip", "lunge", "push up", "push-up", "clean",
    )))


# The scraped prose, photos and brand are the source site's copyrighted material and
# trademarks - only the facts (exercises, sets, reps, schedule, ingredients, macros) are
# imported. Titles, descriptions and summaries shown in the app are our own, generated
# below from those facts; images fall back to the app's bundled artwork.
BRAND_PATTERN = re.compile(r"\s*(muscle\s*(&|and)\s*strength|m&s)('s)?\s*", re.IGNORECASE)

# Titles naming real people or third-party characters/marks, renamed to plain
# descriptive ones (App Review 5.2.1 / 5.2.2: no unlicensed names or trademarks).
TITLE_OVERRIDES = {
    "Michael B. Jordan Inspired Workout (Killmonger)": "5 Day Athletic Hypertrophy Split",
    "Chris Evans Inspired Workout (Captain America)": "4 Day Hero Physique Split",
    "Scarlett Johansson Inspired Workout (Black Widow)": "7 Day Lean Athlete Program",
    "Brie Larson Inspired Workout (Captain Marvel)": "4 Day Strength & Power Split",
    "6 Week Navy SEAL Workout Routine": "6 Week Military-Style Conditioning Routine",
    # The source site's own coined program names, plus titles promising a meal/diet
    # plan that isn't imported.
    "6 Day Push/Pull/Legs (PPL) Split & Meal Plan": "6 Day Push/Pull/Legs (PPL) Split",
    "12 Week Fat Destroyer: Complete Fat Loss Workout & Diet Program": "12 Week Upper/Lower Fat Loss Program",
    "M-F Workout Routine: 5 Day Body Part Split": "5 Day Body Part Split (Mon-Fri)",
    "Power Muscle Burn 5 Day Powerbuilding Split": "5 Day Powerbuilding Split",
    "The Butt Builder Workout": "Glute Focus Workout",
    "Awesome Arms: 8 Weeks to Better Biceps and Triceps": "8 Week Biceps & Triceps Program",
    "4 Week 'V Cuts Abs' Workout Routine": "4 Week Upper/Lower & Abs Routine",
    "Body Like A God: Bodyweight Muscle Building Plan": "Bodyweight Muscle Building Plan",
    "The Best 15-Minute Warm-Ups": "15-Minute Warm-Up Routines",
}

# The same names as they appear inside those programs' day titles
# ("Scarlett Johansson Workout Day 1: Full Body Strength Training").
PERSON_NAME_PATTERN = re.compile(
    r"\b(michael b\. jordan|chris evans|scarlett johansson|brie larson|killmonger|captain america"
    r"|black widow|captain marvel|navy seal)('s)?\s*(inspired\s*)?(workout\s*)?",
    re.IGNORECASE,
)

GOAL_PHRASES = {
    "BuildMuscle": "building muscle",
    "LoseFat": "losing fat while keeping muscle",
    "MaintainActive": "general fitness",
}

CATEGORY_PHRASES = {
    "PHUL": "power and hypertrophy upper/lower",
    "PHAT": "power and hypertrophy",
    "ArnoldSplit": "Arnold-style",
    "PushPullLegs": "push/pull/legs",
    "UpperLower": "upper/lower",
    "Powerlifting": "strength",
    "Calisthenics": "bodyweight",
    "Circuit": "circuit",
    "GluteFocus": "glute-focused",
    "FullBody": "full body",
    "BroSplit": "body-part split",
}


def workout_title(item: dict[str, Any]) -> str:
    title = TITLE_OVERRIDES.get(item["title"], item["title"])
    return BRAND_PATTERN.sub(" ", title).strip()


def workout_description(item: dict[str, Any], days_per_week: int | None, duration_weeks: int | None,
                        min_minutes: int | None, max_minutes: int | None) -> str:
    level = (item.get("experience_level") or "Intermediate").lower()
    style = CATEGORY_PHRASES.get(workout_category(item), "training")
    goal = GOAL_PHRASES.get(workout_goal(item), "general fitness")
    length = f"{duration_weeks}-week " if duration_weeks else ""
    days = f"{days_per_week}-day " if days_per_week else ""
    lead = f"{length}{days}{style}"
    article = "An" if re.match(r"(8|11|18)\b|8\d|[aeiou]", lead) else "A"
    parts = [f"{article} {lead} program for {level} lifters focused on {goal}."]
    if min_minutes and max_minutes and max_minutes != min_minutes:
        parts.append(f"Sessions take about {min_minutes}-{max_minutes} minutes.")
    elif min_minutes:
        parts.append(f"Sessions take about {min_minutes} minutes.")
    equipment = [e.strip().lower() for e in (item.get("equipment_required") or "").split(",") if e.strip()]
    if equipment and equipment != ["none"]:
        parts.append("Equipment: " + ", ".join(equipment).replace("ez bar", "EZ bar") + ".")
    return " ".join(parts)


def day_title(day: dict[str, Any], day_index: int) -> str:
    title = PERSON_NAME_PATTERN.sub("", BRAND_PATTERN.sub(" ", day.get("title") or "")).strip(" :-")
    return title or f"Day {day_index}"


def day_notes(day: dict[str, Any]) -> str | None:
    # Short prescriptions ("Cardio - 30 min low intensity on treadmill") are facts
    # worth keeping; longer notes are the source's commentary and promo text.
    notes = (day.get("notes") or "").strip()
    if (not notes or len(notes) > 160 or BRAND_PATTERN.search(notes) or "@" in notes
            or "comment" in notes.lower() or PERSON_NAME_PATTERN.search(notes)):
        return None
    return notes


def recipe_description(item: dict[str, Any]) -> str | None:
    # Cards already show calories and macros; only call out a notably high-protein
    # recipe. Everything else gets no description rather than the source's blurb.
    kcal = first_number(item.get("calories_kcal"))
    protein = first_number(item.get("protein_g"))
    if not kcal or protein * 4 < kcal * 0.3:
        return None
    meal = meal_type(item.get("categories") or []).lower()
    return f"High-protein {meal} with {protein} g protein per serving."


def meal_type(categories: list[str]) -> str:
    lowered = " ".join(categories).lower()
    if "breakfast" in lowered:
        return "Breakfast"
    if "lunch" in lowered:
        return "Lunch"
    if "dinner" in lowered:
        return "Dinner"
    return "Snack"


def header() -> list[str]:
    return [
        "USE SilenDb;",
        "GO",
        "SET ANSI_NULLS ON;",
        "SET QUOTED_IDENTIFIER ON;",
        "SET NOCOUNT ON;",
        "SET XACT_ABORT ON;",
        "GO",
        "-- Generated by tools/muscleandstrength_scraper/generate_sql.py.",
        "-- Idempotent by source URL; safe to re-run after a refreshed scrape.",
        "",
    ]


def render_workouts(items: list[dict[str, Any]], replace_all: bool = False) -> list[str]:
    selected_urls = ",\n        ".join(sql_text(item["url"], 500) for item in items)
    selection = (
        ["SELECT SplitId INTO #RemovedWorkoutSplits FROM dbo.WorkoutSplits;"]
        if replace_all
        else [
            "SELECT SplitId INTO #RemovedWorkoutSplits FROM dbo.WorkoutSplits",
            "WHERE (SourceUrl LIKE N'https://www.muscleandstrength.com/workouts/%' OR SourceUrl LIKE N'https://www.muscleandstrength.com/content/%')",
            "  AND SourceUrl NOT IN (",
            f"        {selected_urls}",
            "  );",
        ]
    )
    out = [
        "----------------------------------------------------------------------------",
        "-- Selected workout catalog",
        "----------------------------------------------------------------------------",
        "-- Remove every routine outside the selected CSV catalog.",
        "-- Historical sessions and generation deliveries are retained with a NULL split reference.",
        "IF OBJECT_ID(N'tempdb..#RemovedWorkoutSplits') IS NOT NULL DROP TABLE #RemovedWorkoutSplits;",
        *selection,
        "UPDATE dbo.WorkoutSessions SET SplitDayId=NULL",
        "WHERE SplitDayId IN (SELECT SplitDayId FROM dbo.SplitDays WHERE SplitId IN (SELECT SplitId FROM #RemovedWorkoutSplits));",
        "IF OBJECT_ID(N'dbo.WeeklyAiPlanDeliveries', N'U') IS NOT NULL",
        "    UPDATE dbo.WeeklyAiPlanDeliveries SET SplitId=NULL WHERE SplitId IN (SELECT SplitId FROM #RemovedWorkoutSplits);",
        "DELETE FROM dbo.UserActiveSplits WHERE SplitId IN (SELECT SplitId FROM #RemovedWorkoutSplits);",
        "DELETE FROM dbo.SplitDayExercises",
        "WHERE SplitDayId IN (SELECT SplitDayId FROM dbo.SplitDays WHERE SplitId IN (SELECT SplitId FROM #RemovedWorkoutSplits));",
        "DELETE FROM dbo.SplitDays WHERE SplitId IN (SELECT SplitId FROM #RemovedWorkoutSplits);",
        "DELETE FROM dbo.WorkoutSplits WHERE SplitId IN (SELECT SplitId FROM #RemovedWorkoutSplits);",
        "DROP TABLE #RemovedWorkoutSplits;",
        "GO",
        "",
    ]
    exercise_names = workout_exercise_names(items)
    for name in exercise_names:
        out.extend([
            "IF NOT EXISTS (SELECT 1 FROM dbo.Exercises WHERE Name = " + sql_text(name, 150) + ")",
            "    INSERT INTO dbo.Exercises (Name, MuscleGroup, EquipmentType, IsCompound)",
            f"    VALUES ({sql_text(name, 150)}, {sql_text(muscle_group(name))}, {sql_text(equipment_type(name))}, {is_compound(name)});",
        ])
    out.append("GO")

    for item in items:
        popularity_rank = int(item["popularity_rank"]) if item.get("popularity_rank") else None
        catalog_rank = int(item.get("catalog_rank") or 0)
        days = item.get("days") or []
        if not days:
            raise ValueError(f"Workout {item.get('title')!r} has no exercise-bearing workout days")
        duration_days = len(days)
        days_per_week = bounded_number(item.get("days_per_week"), 1, 7, min(7, duration_days))
        duration_weeks = bounded_number(item.get("program_duration"), 1, 520)
        min_minutes, max_minutes = minute_range(item.get("time_per_workout"))
        typical_minutes = round(((min_minutes or 60) + (max_minutes or min_minutes or 60)) / 2)
        popularity_sql = str(popularity_rank) if popularity_rank is not None else "NULL"
        sort_order = 1000 + catalog_rank
        title = workout_title(item)
        description = workout_description(item, days_per_week, duration_weeks, min_minutes, max_minutes)
        out.extend([
            "DECLARE @ImportedSplitId UNIQUEIDENTIFIER;",
            "DECLARE @ImportedDayId UNIQUEIDENTIFIER;",
            "DECLARE @ImportedExerciseId UNIQUEIDENTIFIER;",
            "SELECT TOP (1) @ImportedSplitId = SplitId FROM dbo.WorkoutSplits",
            f"WHERE SourceUrl = {sql_text(item['url'])} OR (SourceUrl IS NULL AND Name = {sql_text(title, 150)});",
            "IF @ImportedSplitId IS NULL",
            "BEGIN",
            "    SET @ImportedSplitId = NEWID();",
            "    INSERT INTO dbo.WorkoutSplits",
            "        (SplitId, Name, Category, Level, DurationDays, Description, HeroImageUrl, IsSystemDefault, SortOrder, RecommendedGoal, Visibility, SourceUrl, SourceAuthor, FullDescription, PopularityRank, PopularityWindow, DaysPerWeek, ProgramDurationWeeks, MinSessionMinutes, MaxSessionMinutes, EquipmentRequired, TargetGender, WorkoutTypeLabel, SourceCategoriesJson, CatalogRank)",
            f"    VALUES (@ImportedSplitId, {sql_text(title, 150)}, {sql_text(workout_category(item))}, {sql_text(item.get('experience_level') or 'Intermediate')}, {duration_days}, {sql_text(description, 500)}, NULL, 1, {sort_order}, {sql_text(workout_goal(item))}, N'Public', {sql_text(item['url'])}, NULL, NULL, {popularity_sql}, {sql_text(item.get('popularity_window'), 100)}, {days_per_week}, {duration_weeks if duration_weeks is not None else 'NULL'}, {min_minutes if min_minutes is not None else 'NULL'}, {max_minutes if max_minutes is not None else 'NULL'}, {sql_text(item.get('equipment_required'), 500)}, {sql_text(item.get('target_gender'), 50)}, {sql_text(item.get('workout_type'), 100)}, {sql_json(item.get('source_categories') or [])}, {catalog_rank});",
            "END",
            "ELSE",
            "BEGIN",
            "    UPDATE dbo.WorkoutSplits SET",
            f"        Name={sql_text(title, 150)}, Category={sql_text(workout_category(item))}, Level={sql_text(item.get('experience_level') or 'Intermediate')}, DurationDays={duration_days},",
            f"        Description={sql_text(description, 500)}, HeroImageUrl=NULL, IsSystemDefault=1, SortOrder={sort_order},",
            f"        RecommendedGoal={sql_text(workout_goal(item))}, Visibility=N'Public', SourceUrl={sql_text(item['url'])},",
            "        SourceAuthor=NULL, FullDescription=NULL, PopularityRank=" + popularity_sql + ", PopularityWindow=" + sql_text(item.get('popularity_window'), 100) + ",",
            f"        DaysPerWeek={days_per_week}, ProgramDurationWeeks={duration_weeks if duration_weeks is not None else 'NULL'}, MinSessionMinutes={min_minutes if min_minutes is not None else 'NULL'}, MaxSessionMinutes={max_minutes if max_minutes is not None else 'NULL'}, EquipmentRequired={sql_text(item.get('equipment_required'), 500)}, TargetGender={sql_text(item.get('target_gender'), 50)}, WorkoutTypeLabel={sql_text(item.get('workout_type'), 100)}, SourceCategoriesJson={sql_json(item.get('source_categories') or [])}, CatalogRank={catalog_rank}",
            "    WHERE SplitId=@ImportedSplitId;",
            "END",
        ])
        for day_index, day in enumerate(days, start=1):
            out.extend([
                "SET @ImportedDayId=NULL;",
                f"SELECT @ImportedDayId=SplitDayId FROM dbo.SplitDays WHERE SplitId=@ImportedSplitId AND DayIndex={day_index};",
                "IF @ImportedDayId IS NULL",
                "BEGIN",
                "    SET @ImportedDayId=NEWID();",
                "    INSERT INTO dbo.SplitDays (SplitDayId, SplitId, DayIndex, Title, FocusLabel, EstimatedMinutes, IsRestDay, SourceNotes)",
                f"    VALUES (@ImportedDayId, @ImportedSplitId, {day_index}, {sql_text(day_title(day, day_index), 150)}, {sql_text(item.get('workout_type'), 100)}, {0 if day.get('is_rest_day') else typical_minutes}, {1 if day.get('is_rest_day') else 0}, {sql_text(day_notes(day))});",
                "END",
                "ELSE UPDATE dbo.SplitDays SET",
                f"    Title={sql_text(day_title(day, day_index), 150)}, FocusLabel={sql_text(item.get('workout_type'), 100)}, EstimatedMinutes={0 if day.get('is_rest_day') else typical_minutes}, IsRestDay={1 if day.get('is_rest_day') else 0}, SourceNotes={sql_text(day_notes(day))}",
                "    WHERE SplitDayId=@ImportedDayId;",
                "DELETE FROM dbo.SplitDayExercises WHERE SplitDayId=@ImportedDayId;",
            ])
            rows: list[tuple[str, dict[str, Any]]] = []
            for table in day.get("exercise_tables", []) or []:
                if not isinstance(table, list):
                    continue
                for row in table:
                    if not isinstance(row, dict):
                        continue
                    name = normalize_exercise_name(exercise_value(row, "Exercise"))
                    if name:
                        rows.append((name, row))
            for sort_order, (exercise, row) in enumerate(rows, start=1):
                source_reps = exercise_value(row, "Reps")
                source_sets = exercise_value(row, "Sets")
                low, high = rep_range(source_reps)
                sets = max(1, min(20, first_number(source_sets, 1)))
                out.extend([
                    "SET @ImportedExerciseId=(SELECT TOP (1) ExerciseId FROM dbo.Exercises WHERE Name=" + sql_text(exercise, 150) + ");",
                    "    INSERT INTO dbo.SplitDayExercises (SplitDayId, ExerciseId, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh, SourceSets, SourceReps)",
                    f"    VALUES (@ImportedDayId, @ImportedExerciseId, {sort_order}, {sets}, {low}, {high}, {sql_text(source_sets, 100)}, {sql_text(source_reps, 300)});",
                ])
        out.extend([
            "UPDATE dbo.WorkoutSessions SET SplitDayId=NULL",
            f"WHERE SplitDayId IN (SELECT SplitDayId FROM dbo.SplitDays WHERE SplitId=@ImportedSplitId AND (DayIndex<1 OR DayIndex>{len(days)}));",
            "DELETE FROM dbo.SplitDayExercises",
            f"WHERE SplitDayId IN (SELECT SplitDayId FROM dbo.SplitDays WHERE SplitId=@ImportedSplitId AND (DayIndex<1 OR DayIndex>{len(days)}));",
            f"DELETE FROM dbo.SplitDays WHERE SplitId=@ImportedSplitId AND (DayIndex<1 OR DayIndex>{len(days)});",
        ])
        out.extend(["GO", ""])
    return out


def render_diets() -> list[str]:
    # The diet guides were long-form articles copied from the source site. They are
    # no longer imported; this removes any rows an earlier version of this seed wrote.
    return [
        "----------------------------------------------------------------------------",
        "-- Remove previously imported diet-guide articles (source site's copyrighted text)",
        "----------------------------------------------------------------------------",
        "DELETE FROM dbo.DietPlanSections",
        "WHERE DietPlanId IN (SELECT DietPlanId FROM dbo.DietPlans WHERE SourceUrl LIKE N'https://www.muscleandstrength.com/%');",
        "DELETE FROM dbo.DietPlans WHERE SourceUrl LIKE N'https://www.muscleandstrength.com/%';",
        "GO",
        "",
    ]


def render_recipes(items: list[dict[str, Any]]) -> list[str]:
    out = ["----------------------------------------------------------------------------", "-- Recipes and normalized ingredients/instructions", "----------------------------------------------------------------------------"]
    ordered = sorted(items, key=lambda x: (-(x.get("read_count") or 0), x["title"].casefold()))
    for sort_order, item in enumerate(ordered, start=1):
        categories = item.get("categories") or []
        macros = {key: item.get(key) for key in ("calories_kcal", "protein_g", "carbs_g", "fat_g")}
        out.extend([
            "DECLARE @ImportedMealSuggestionId UNIQUEIDENTIFIER;",
            "SELECT TOP (1) @ImportedMealSuggestionId=MealSuggestionId FROM dbo.MealSuggestions",
            f"WHERE SourceUrl={sql_text(item['url'])} OR (SourceUrl IS NULL AND Title={sql_text(item['title'], 200)});",
            "IF @ImportedMealSuggestionId IS NULL",
            "BEGIN",
            "    SET @ImportedMealSuggestionId=NEWID();",
            "    INSERT INTO dbo.MealSuggestions",
            "        (MealSuggestionId, Title, MealType, Description, CaloriesKcal, ProteinG, CarbsG, FatsG, SuggestedMonth, IsSystemDefault, SortOrder, SourceUrl, ImageUrl, ServingSuggestion, ContentText, CategoriesJson, SourceMacrosJson, ReadCount)",
            f"    VALUES (@ImportedMealSuggestionId, {sql_text(item['title'], 200)}, {sql_text(meal_type(categories))}, {sql_text(recipe_description(item), 500)}, {first_number(item.get('calories_kcal'))}, {first_number(item.get('protein_g'))}, {first_number(item.get('carbs_g'))}, {first_number(item.get('fat_g'))}, NULL, 1, {10000 + sort_order}, {sql_text(item['url'], 500)}, NULL, NULL, NULL, {sql_json(categories)}, {sql_json(macros)}, {item.get('read_count') or 'NULL'});",
            "END",
            "ELSE UPDATE dbo.MealSuggestions SET",
            f"    Title={sql_text(item['title'], 200)}, MealType={sql_text(meal_type(categories))}, Description={sql_text(recipe_description(item), 500)}, CaloriesKcal={first_number(item.get('calories_kcal'))}, ProteinG={first_number(item.get('protein_g'))}, CarbsG={first_number(item.get('carbs_g'))}, FatsG={first_number(item.get('fat_g'))},",
            f"    SuggestedMonth=NULL, IsSystemDefault=1, SortOrder={10000 + sort_order}, SourceUrl={sql_text(item['url'], 500)}, ImageUrl=NULL, ServingSuggestion=NULL, ContentText=NULL, CategoriesJson={sql_json(categories)}, SourceMacrosJson={sql_json(macros)}, ReadCount={item.get('read_count') or 'NULL'}",
            "    WHERE MealSuggestionId=@ImportedMealSuggestionId;",
            "DELETE FROM dbo.MealSuggestionIngredients WHERE MealSuggestionId=@ImportedMealSuggestionId;",
        ])
        for ingredient_order, ingredient in enumerate(item.get("ingredients", []), start=1):
            out.append(f"INSERT INTO dbo.MealSuggestionIngredients (MealSuggestionId, SortOrder, IngredientText) VALUES (@ImportedMealSuggestionId, {ingredient_order}, {sql_text(ingredient, 1000)});")
        # Ingredient lists and macros are facts; the method text is the source's prose.
        out.append("DELETE FROM dbo.MealSuggestionInstructions WHERE MealSuggestionId=@ImportedMealSuggestionId;")
        out.extend(["GO", ""])
    return out


def generate(
    input_dir: Path,
    output: Path,
    replace_all_workouts: bool = False,
    workouts_only: bool = False,
) -> None:
    workouts = json.loads((input_dir / "workouts.json").read_text(encoding="utf-8"))
    recipes = [] if workouts_only else json.loads((input_dir / "recipes.json").read_text(encoding="utf-8"))
    lines = header()
    lines.extend(["BEGIN TRANSACTION;", "GO", ""])
    lines.extend(render_workouts(workouts, replace_all_workouts))
    if not workouts_only:
        lines.extend(render_diets())
        lines.extend(render_recipes(recipes))
    lines.extend([
        "SELECT",
        "    (SELECT COUNT(*) FROM dbo.WorkoutSplits WHERE SourceUrl LIKE N'https://www.muscleandstrength.com/workouts/%' OR SourceUrl LIKE N'https://www.muscleandstrength.com/content/%') AS ImportedWorkouts,",
        "    (SELECT COUNT(*) FROM dbo.DietPlans WHERE SourceUrl LIKE N'https://www.muscleandstrength.com/diet-plans/%') AS ImportedDietPlans,",
        "    (SELECT COUNT(*) FROM dbo.MealSuggestions WHERE SourceUrl LIKE N'https://www.muscleandstrength.com/%') AS ImportedRecipes,",
        "    (SELECT COUNT(*) FROM dbo.MealSuggestionIngredients i INNER JOIN dbo.MealSuggestions m ON m.MealSuggestionId=i.MealSuggestionId WHERE m.SourceUrl LIKE N'https://www.muscleandstrength.com/%') AS ImportedIngredients;",
        "GO",
        "",
    ])
    if replace_all_workouts:
        lines.extend([
            f"IF (SELECT COUNT(*) FROM dbo.WorkoutSplits) <> {len(workouts)}",
            f"    THROW 51000, 'Expected exactly {len(workouts)} workout splits after replacement.', 1;",
        ])
    lines.extend(["COMMIT TRANSACTION;", "GO", ""])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines), encoding="utf-8")
    print(f"Generated {output} from {len(workouts)} workouts and {len(recipes)} recipes")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--replace-all-workouts",
        action="store_true",
        help="Delete every existing workout split before inserting the selected workout catalog.",
    )
    parser.add_argument(
        "--workouts-only",
        action="store_true",
        help="Generate only the workout catalog portion of the import.",
    )
    args = parser.parse_args()
    generate(args.input_dir, args.output, args.replace_all_workouts, args.workouts_only)


if __name__ == "__main__":
    main()
