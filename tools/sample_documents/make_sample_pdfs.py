"""Builds two sample trainer documents for testing the locked-PDF flow.

* test-split.pdf     - "Test Split": 4 training days a week, two different weeks
                       (week 2 progresses), so the importer's multi-week numbering
                       and the split detail's document action can both be checked.
* weekly-diet-plan.pdf - "Test Weekly Diet Plan": 7 days, 4 meals a day, with
                       macros, ingredients and steps written out.

Upload them in the admin console (Documents -> Upload, kind Split / DietPlan,
"generate" on to build a private program, or attach to an existing one), assign
them to a test user, then open them in the app.

    python3 -m venv .venv && .venv/bin/pip install "reportlab<4.1"   # 4.1+ needs Python 3.10
    .venv/bin/python tools/sample_documents/make_sample_pdfs.py
"""

from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import (
    KeepTogether,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

OUT = Path(__file__).resolve().parent
ACCENT = colors.HexColor("#FF5A1F")
INK = colors.HexColor("#1C1C1E")
MUTED = colors.HexColor("#6B6B70")
ROW = colors.HexColor("#F4F4F5")

styles = getSampleStyleSheet()
H1 = ParagraphStyle("H1", parent=styles["Title"], textColor=INK, fontSize=24, spaceAfter=4, alignment=0)
SUB = ParagraphStyle("Sub", parent=styles["Normal"], textColor=MUTED, fontSize=10, spaceAfter=10)
H2 = ParagraphStyle("H2", parent=styles["Heading2"], textColor=ACCENT, fontSize=15, spaceBefore=10, spaceAfter=4)
H3 = ParagraphStyle("H3", parent=styles["Heading3"], textColor=INK, fontSize=12, spaceBefore=8, spaceAfter=3)
BODY = ParagraphStyle("Body", parent=styles["Normal"], textColor=INK, fontSize=9.5, leading=13)
SMALL = ParagraphStyle("Small", parent=BODY, fontSize=8.5, leading=11, textColor=MUTED)


def footer(canvas, doc):
    canvas.saveState()
    canvas.setFont("Helvetica", 8)
    canvas.setFillColor(MUTED)
    canvas.drawString(18 * mm, 10 * mm, "SilaFit test document - not for distribution")
    canvas.drawRightString(A4[0] - 18 * mm, 10 * mm, f"Page {doc.page}")
    canvas.restoreState()


def table(rows, widths):
    t = Table(rows, colWidths=widths, repeatRows=1)
    style = [
        ("BACKGROUND", (0, 0), (-1, 0), INK),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ]
    for i in range(1, len(rows)):
        if i % 2 == 0:
            style.append(("BACKGROUND", (0, i), (-1, i), ROW))
    t.setStyle(TableStyle(style))
    return t


def build(path, story):
    doc = SimpleDocTemplate(
        str(path), pagesize=A4, leftMargin=18 * mm, rightMargin=18 * mm,
        topMargin=16 * mm, bottomMargin=18 * mm,
        title=path.stem, author="SilaFit Test Coach",
    )
    doc.build(story, onFirstPage=footer, onLaterPages=footer)
    print(f"wrote {path}")


# ----------------------------------------------------------------- split

# (weekday, title, focus, minutes, [(exercise, sets, reps, notes)])
WEEK_1 = [
    ("Monday", "Upper A", "Chest & Back", 60, [
        ("Bench Press", 4, "6-8", "2 min rest, last set RPE 8"),
        ("Bent Over Row", 4, "8-10", "Barbell, overhand grip"),
        ("Incline Dumbbell Press", 3, "10-12", ""),
        ("Lat Pulldown", 3, "10-12", "Wide grip"),
        ("Face Pull", 3, "15", "Cable, rope attachment"),
        ("Bicep Curl", 3, "12", "Dumbbell"),
    ]),
    ("Tuesday", "Lower A", "Quads & Glutes", 55, [
        ("Back Squat", 4, "6-8", "Barbell, 2-3 min rest"),
        ("Romanian Deadlift", 3, "8-10", ""),
        ("Leg Press", 3, "12", ""),
        ("Walking Lunge", 3, "10", "Each leg, holding dumbbells"),
        ("Calf Raise", 4, "15", ""),
    ]),
    ("Wednesday", "Rest", None, None, []),
    ("Thursday", "Upper B", "Shoulders & Arms", 55, [
        ("Overhead Press", 4, "6-8", "Barbell, standing"),
        ("Pull Up", 4, "6-10", "Add weight if you hit 10"),
        ("Lateral Raise", 3, "12-15", "Dumbbell"),
        ("Seated Cable Row", 3, "10-12", ""),
        ("Tricep Pushdown", 3, "12", "Cable"),
        ("Hammer Curl", 3, "12", ""),
    ]),
    ("Friday", "Lower B", "Hamstrings & Core", 50, [
        ("Deadlift", 3, "5", "Conventional, 3 min rest"),
        ("Bulgarian Split Squat", 3, "8-10", "Each leg"),
        ("Hip Thrust", 3, "10-12", "Barbell"),
        ("Leg Curl", 3, "12", "Machine"),
        ("Plank", 3, "1", "Hold 45 seconds"),
    ]),
    ("Saturday", "Rest", None, None, []),
    ("Sunday", "Rest", None, None, []),
]


def progress(week):
    """Week 2: one extra set on the main lift of each day, heavier rep targets."""
    heavier = {"6-8": "5-7", "8-10": "6-8", "10-12": "8-10", "5": "4"}
    out = []
    for day, title, focus, minutes, exercises in week:
        new = []
        for i, (name, sets, reps, notes) in enumerate(exercises):
            if i == 0:
                sets += 1
            new.append((name, sets, heavier.get(reps, reps), notes))
        out.append((day, title, focus, (minutes + 5) if minutes else None, new))
    return out


def split_week(story, number, week, intro):
    story.append(Paragraph(f"Week {number}", H2))
    story.append(Paragraph(intro, BODY))
    for day, title, focus, minutes, exercises in week:
        if not exercises:
            story.append(Paragraph(f"{day} - Rest day", H3))
            story.append(Paragraph("No training. Walk 20-30 minutes, stretch, sleep 8 hours.", SMALL))
            continue
        block = [
            Paragraph(f"{day} - {title} ({focus})", H3),
            Paragraph(f"Estimated time: {minutes} minutes", SMALL),
            Spacer(1, 3),
        ]
        rows = [["Exercise", "Sets", "Reps", "Notes"]]
        for name, sets, reps, notes in exercises:
            rows.append([name, str(sets), reps, Paragraph(notes or "-", BODY)])
        block.append(table(rows, [62 * mm, 16 * mm, 20 * mm, 76 * mm]))
        story.append(KeepTogether(block))


def make_split():
    story = [
        Paragraph("Test Split", H1),
        Paragraph("4-day Upper / Lower program - Intermediate - 2-week block - Coach: SilaFit Test Coach", SUB),
        Paragraph(
            "Train four days a week: Upper A, Lower A, rest, Upper B, Lower B, then two rest days. "
            "Warm up 10 minutes before every session (5 minutes bike, then 2 light sets of the first lift). "
            "Week 2 adds a set to the first exercise of each day and lowers the rep target so the weight goes up.",
            BODY,
        ),
    ]
    split_week(story, 1, WEEK_1, "Foundation week. Leave 2 reps in the tank on every set.")
    story.append(PageBreak())
    split_week(story, 2, progress(WEEK_1), "Progression week. Add 2.5-5 kg to the main lifts compared to week 1.")
    build(OUT / "test-split.pdf", story)


# ----------------------------------------------------------------- diet

# (type, title, kcal, protein, carbs, fats, ingredients, steps)
M = lambda *a: a  # noqa: E731

BREAKFASTS = [
    M("Breakfast", "Oats with whey and berries", 520, 38, 68, 11,
      ["80 g rolled oats", "30 g whey protein", "100 g blueberries", "250 ml skim milk", "10 g honey"],
      ["Cook the oats in the milk for 4 minutes.", "Take off the heat and stir in the whey.", "Top with blueberries and honey."]),
    M("Breakfast", "Scrambled eggs on toast", 480, 32, 40, 20,
      ["3 eggs", "100 g egg whites", "2 slices wholegrain bread", "50 g spinach", "5 g butter"],
      ["Whisk eggs and egg whites.", "Wilt the spinach in the butter, add the eggs and stir on low heat.", "Serve on toasted bread."]),
    M("Breakfast", "Greek yogurt bowl", 450, 35, 52, 11,
      ["300 g Greek yogurt 2%", "40 g granola", "1 banana", "10 g chia seeds"],
      ["Spoon the yogurt into a bowl.", "Slice the banana on top.", "Sprinkle with granola and chia."]),
]

LUNCHES = [
    M("Lunch", "Chicken rice bowl", 650, 50, 75, 14,
      ["180 g chicken breast", "90 g basmati rice (dry)", "150 g broccoli", "10 ml olive oil", "Soy sauce"],
      ["Cook the rice.", "Grill the chicken 6 minutes per side and slice.", "Steam the broccoli and serve everything with soy sauce."]),
    M("Lunch", "Tuna pasta salad", 620, 45, 72, 15,
      ["90 g wholewheat pasta (dry)", "1 can tuna in water (150 g)", "100 g cherry tomatoes", "50 g sweetcorn", "10 ml olive oil"],
      ["Boil the pasta and cool under cold water.", "Mix with drained tuna, halved tomatoes and corn.", "Dress with olive oil, salt and pepper."]),
    M("Lunch", "Turkey wrap", 580, 42, 60, 17,
      ["2 wholewheat tortillas", "150 g sliced turkey breast", "30 g light cream cheese", "Lettuce", "1 tomato"],
      ["Spread cream cheese on the tortillas.", "Layer turkey, lettuce and sliced tomato.", "Roll tightly and cut in half."]),
]

DINNERS = [
    M("Dinner", "Salmon with potatoes", 640, 42, 50, 27,
      ["170 g salmon fillet", "250 g baby potatoes", "150 g green beans", "1 lemon"],
      ["Roast the halved potatoes at 200 C for 25 minutes.", "Add the salmon for the last 12 minutes.", "Boil the green beans 4 minutes, serve with lemon."]),
    M("Dinner", "Lean beef stir-fry", 610, 46, 55, 20,
      ["160 g lean beef strips", "80 g rice noodles (dry)", "1 bell pepper", "100 g snap peas", "15 ml soy sauce", "5 ml sesame oil"],
      ["Soak the noodles.", "Stir-fry the beef in sesame oil for 3 minutes, add the vegetables for 3 more.", "Toss with noodles and soy sauce."]),
    M("Dinner", "Chicken chili", 590, 48, 58, 14,
      ["150 g minced chicken", "120 g kidney beans", "200 g chopped tomatoes", "1 onion", "Chili powder, cumin"],
      ["Brown the chicken with the diced onion.", "Add spices, tomatoes and beans.", "Simmer 20 minutes."]),
]

SNACKS = [
    M("Snack", "Protein shake and apple", 280, 26, 32, 4,
      ["30 g whey protein", "300 ml water", "1 apple"], ["Shake the whey with water.", "Eat with the apple."]),
    M("Snack", "Cottage cheese and almonds", 300, 28, 10, 16,
      ["200 g cottage cheese", "20 g almonds"], ["Serve the cottage cheese topped with almonds."]),
    M("Snack", "Rice cakes with peanut butter", 290, 10, 34, 13,
      ["3 rice cakes", "20 g peanut butter", "1/2 banana"], ["Spread peanut butter on the rice cakes and top with banana slices."]),
]

DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]


def make_diet():
    story = [
        Paragraph("Test Weekly Diet Plan", H1),
        Paragraph("7-day plan - about 2,100 kcal and 160 g protein a day - Coach: SilaFit Test Coach", SUB),
        Paragraph(
            "Four meals a day. Weigh food raw unless stated. Swap meals within the same type if needed.",
            BODY,
        ),
    ]
    for d, day in enumerate(DAYS):
        meals = [BREAKFASTS[d % 3], LUNCHES[(d + 1) % 3], DINNERS[(d + 2) % 3], SNACKS[d % 3]]
        kcal = sum(m[2] for m in meals)
        protein = sum(m[3] for m in meals)
        story.append(Paragraph(f"Day {d + 1} - {day}", H2))
        story.append(Paragraph(f"Day total: {kcal} kcal - {protein} g protein", SMALL))
        for kind, title, cal, p, c, f, ingredients, steps in meals:
            rows = [[f"{kind}: {title}", f"{cal} kcal", f"P {p} g", f"C {c} g", f"F {f} g"]]
            rows.append([
                Paragraph("<b>Ingredients</b><br/>" + "<br/>".join(f"- {i}" for i in ingredients), BODY), "", "", "", "",
            ])
            rows.append([
                Paragraph("<b>Steps</b><br/>" + "<br/>".join(f"{n}. {s}" for n, s in enumerate(steps, 1)), BODY), "", "", "", "",
            ])
            t = Table(rows, colWidths=[86 * mm, 22 * mm, 22 * mm, 22 * mm, 22 * mm])
            t.setStyle(TableStyle([
                ("BACKGROUND", (0, 0), (-1, 0), INK),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("FONTSIZE", (0, 0), (-1, 0), 9),
                ("SPAN", (0, 1), (-1, 1)),
                ("SPAN", (0, 2), (-1, 2)),
                ("BACKGROUND", (0, 1), (-1, 2), ROW),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ]))
            story.append(KeepTogether([t, Spacer(1, 5)]))
        if d < len(DAYS) - 1:
            story.append(PageBreak())
    build(OUT / "weekly-diet-plan.pdf", story)


if __name__ == "__main__":
    make_split()
    make_diet()
