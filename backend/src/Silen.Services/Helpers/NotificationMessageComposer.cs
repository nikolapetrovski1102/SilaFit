using Silen.Common.Models;

namespace Silen.Services.Helpers;

/// <summary>A composed push message: what to say and which screen to open.</summary>
public sealed record NotificationContent(string Title, string Body, string Screen);

/// <summary>
/// Writes the actual push copy. Every category has several templates per
/// language register and the pick is stable per (user, local day, category), so
/// a given user gets variety day to day but the same message within a run -
/// re-running the batch never reshuffles what was already decided.
///
/// Copy is intentionally short, lowercase-friendly and a little unserious
/// (Gen Z register) because it is competing with social notifications for a
/// tap. Names are used when we have them, and every template reads correctly
/// without a name.
/// </summary>
public static class NotificationMessageComposer
{
    public static NotificationContent GymReminder(NotificationCandidateModel candidate, DateOnly localDate) =>
        Pick(candidate, localDate, NotificationCategories.GymReminder, "today",
            ("gym o'clock 🏋️", $"{Name(candidate)}, reservation for one at the squat rack. let's move."),
            ("your workout is waiting", $"{Name(candidate)}, the weights aren't gonna lift themselves."),
            ("bestie. gym. now.", "one session today = tomorrow-you saying ty. you in?"),
            ("quick ✅ for today", "sweat first, scroll later. your split is ready."),
            ("no excuses era 🚫", "even a short session counts. lock in for 30 minutes."),
            ("it's giving gym energy", "show up for the version of you that started this."),
            ("leg day said hi 👋", "your plan is loaded and waiting. let's get after it."),
            ("the pre-workout plot twist", "you actually go train. open your plan and start the first set."),
            ("time to lock in 🔒", "your workout window is here. one tap and you're moving."),
            ("soft launch your gains", "today's session is ready. low drama, high protein, let's go."),
            ("proof > promises", "clock in, get the work done, collect the post-workout glow."),
            ("your split entered the chat", "it brought sets, reps, and zero interest in excuses."));

    public static NotificationContent TrackSets(NotificationCandidateModel candidate, TimeSpan idle, DateOnly localDate) =>
        Pick(candidate, localDate, NotificationCategories.TrackSets, "workout",
            ("log those sets 📝", "you've been quiet a minute — tap them in before your brain forgets."),
            ("sets > vibes", "don't leave them unlogged. your PRs need receipts."),
            ("quick one 🫡", "log the set, rest, repeat. future-you is watching."),
            ("don't ghost the log", $"{(int)idle.TotalMinutes} min since the last one. drop it in real quick."),
            ("receipts 📋", "unlogged sets don't count. keep the session honest."),
            ("did the set even happen?", "no log, no lore. add the reps while they're fresh."),
            ("tiny admin moment", "tap in the set, then get back to being strong."),
            ("the log is on read", "give it the reps and weight. your progress chart deserves context."),
            ("document the damage 💪", "weights up? reps up? put it on the record."));

    public static NotificationContent TrackCalories(NotificationCandidateModel candidate, DateOnly localDate) =>
        Pick(candidate, localDate, NotificationCategories.TrackCalories, "meals",
            ("calories check 🍽️", "what did you eat? 10 seconds now saves the guesswork."),
            ("food log looking a lil empty 👀", "log your meals so we can keep the plan honest."),
            ("no gatekeeping the plate", "drop today's food in and we'll do the math."),
            ("on track?", "log it and we'll tell you exactly where you stand vs your target."),
            ("don't lowball the log", "track it now so the numbers actually mean something."),
            ("macro check, no judgment", "tell us what was on the plate. we'll handle the numbers."),
            ("your protein has receipts, right?", "log the meal and see where today's targets stand."),
            ("quick plate audit", "add what you ate before selective memory kicks in."),
            ("feed the data 🥣", "one fast log keeps your plan personal instead of guessy."));

    public static NotificationContent MealIdea(NotificationCandidateModel candidate, DateOnly localDate) =>
        Pick(candidate, localDate, NotificationCategories.MealIdea, "meals",
            ("dinner idea, zero stress 🍗", "high protein, low effort — peep the meal tab."),
            ("hungry + no plan = chaos", "we got meal ideas that fit your targets. take a look."),
            ("what's for dinner? 🧑‍🍳", "let us pick something that hits your protein goal."),
            ("meal inspo dropped", "fresh ideas that fit your macros. go grab one."),
            ("the fridge is empty, your excuses aren't", "we've got a meal for that. check the ideas."),
            ("protein, but make it good", "your next meal can hit the target without tasting like homework."),
            ("dinner side quest unlocked", "pick a meal that fits the plan and still passes the vibe check."),
            ("your macros ordered room service", "the meal ideas are ready. sadly, you still have to cook."),
            ("less scrolling, more seasoning", "we found a meal that fits. go make something elite."));

    public static NotificationContent Motivation(NotificationCandidateModel candidate, DateOnly localDate) =>
        Pick(candidate, localDate, NotificationCategories.Motivation, "progress",
            ($"{candidate.WorkoutsLast7Days} sessions this week 🔥", "you're actually locked in. keep it rolling."),
            ("consistency > motivation", $"{candidate.WorkoutsLast7Days} workouts logged — that's the whole secret."),
            ("you're on a heater 🧊", $"{candidate.WorkoutsLast7Days} sessions this week. don't stop now."),
            ("look at you go", $"{candidate.WorkoutsLast7Days} workouts this week. the progress is real."),
            ("main character training arc", "showing up repeatedly is the flex. keep going."),
            ("the streak is streaking", $"{candidate.WorkoutsLast7Days} sessions down. momentum looks good on you."),
            ("quietly becoming unstoppable", "no big speech. just more proof that consistency works."),
            ("plot armor: consistency", "you keep showing up and the numbers keep moving. funny how that works."),
            ("okay athlete 👀", "your week is looking strong. keep the standard where it is."));

    public static NotificationContent Comeback(NotificationCandidateModel candidate, DateOnly localDate) =>
        Pick(candidate, localDate, NotificationCategories.Comeback, "today",
            ("you made a rest, let's get back to the gym 💪", "your split missed you. one session to get back in rhythm."),
            ("rest day's over 👀", $"{Name(candidate)}, we saved your spot at the gym. come back stronger."),
            ("gym misses you, fr", "a quick session today resets everything. you got this."),
            ("we don't do ghosting here 👻", "come back and we'll pretend the break never happened."),
            ("back to it?", "one workout is all it takes to feel like you again."),
            ("round 2 starts now", "you've rested enough. let's get one in."),
            ("the comeback arc starts here", "nothing dramatic. just open the plan and do the first exercise."),
            ("still got it, btw", "take the smallest win: show up, warm up, see what happens."),
            ("your routine wants a reboot", "one session today and we're officially back."),
            ("no guilt, just reps", "the break happened. cool. now let's build the next streak."));

    /// <summary>
    /// Monthly review upsell - non-paying users only. Points at the Progress tab
    /// where the locked AI review lives (the "screen" deep link the client routes on).
    /// </summary>
    public static NotificationContent MonthlyReviewUpsell(NotificationCandidateModel candidate, DateOnly localDate) =>
        Pick(candidate, localDate, NotificationCategories.MonthlyReviewUpsell, "progress",
            ("your month, reviewed 🔍", "the AI review of your training is one unlock away. see what improved and what to fix."),
            ("the part your log can't explain", "your numbers are in. the coaching read on them is waiting in PRO."),
            ("monthly review is waiting", $"{Name(candidate)}, unlock PRO and get your full month read by your AI coach."),
            ("data in. verdict pending.", "you logged the month. unlock the review that tells you what to do with it."),
            ("what actually improved?", "your numbers know. unlock the full AI review and hear it."),
            ("your training lore, decoded", "unlock the AI read on what worked, what stalled, and what's next."),
            ("the month has receipts", "your full progress breakdown is ready in PRO. go see the plot."));

    /// <summary>
    /// Sunday "your AI plan is ready" push - sent directly by
    /// WeeklyPlanGenerationService for one user at a time, outside the
    /// candidate-scanning pipeline the other categories go through, so this
    /// takes a bare userId/displayName rather than a full
    /// <see cref="NotificationCandidateModel"/>. Points at "splits" (My
    /// Splits), where the freshly generated split - and a link into the new
    /// diet plan - both land.
    /// </summary>
    public static NotificationContent WeeklyAiPlanReady(Guid userId, string? displayName, bool splitKept = false)
    {
        var templates = splitKept ? WeeklyAiPlanReadyKeptSplitTemplates : WeeklyAiPlanReadyTemplates;
        var index = StableIndex(userId, DateOnly.FromDateTime(DateTime.UtcNow), NotificationCategories.WeeklyAiPlanReady, templates.Length);
        var (title, body) = templates[index];
        return new NotificationContent(title, body.Replace("{name}", Name(displayName)), "splits");
    }

    private static readonly (string Title, string Body)[] WeeklyAiPlanReadyTemplates =
    [
        ("your week, planned 🗓️", "{name}, your AI split and diet plan for this week are ready. take a look."),
        ("fresh plan just dropped", "{name}, a new split and meal plan built from last week's log. check it out."),
        ("this week, sorted ✅", "your AI coach built next week's training and food plan. it's in My Splits."),
        ("no more guessing this week", "{name}, your personalized split + diet plan are ready to go."),
        ("built from your data 📊", "last week's training became this week's plan. go see it."),
        ("new week, new lore", "{name}, your AI-built training and meal plan just landed."),
        ("the plan understood the assignment", "your workouts and meals are mapped out. all that's left is the doing."),
        ("coach cooked 🔥", "your fresh split + meal plan are live. open My Splits and see what's next."),
    ];

    // Sent when the model decided the user's current split already fits, so only
    // the meals (and their shopping list) actually changed this week.
    private static readonly (string Title, string Body)[] WeeklyAiPlanReadyKeptSplitTemplates =
    [
        ("your week's meals are ready 🍽️", "{name}, your split already looked right, so we kept it. this week's meal plan and shopping list are ready."),
        ("split kept, meals refreshed", "{name}, no training changes needed this week. your new meal plan is waiting."),
        ("this week's food, sorted ✅", "your current split still fits. we built the week's meals and shopping list - take a look."),
        ("meals planned, split kept", "{name}, we kept your split and planned your week of meals. check the shopping list."),
        ("same split, fresh menu", "your training plan still passes the vibe check. this week's meals are ready."),
        ("if it fits, we keep it", "{name}, your split stays. your meal plan and shopping list just got a refresh."),
    ];

    private static NotificationContent Pick(
        NotificationCandidateModel candidate,
        DateOnly localDate,
        string category,
        string screen,
        params (string Title, string Body)[] templates)
    {
        var index = StableIndex(candidate.UserId, localDate, category, templates.Length);
        var (title, body) = templates[index];
        return new NotificationContent(title, body, screen);
    }

    private static int StableIndex(Guid userId, DateOnly localDate, string category, int count)
    {
        if (count <= 1)
        {
            return 0;
        }

        unchecked
        {
            var hash = 17;
            foreach (var b in userId.ToByteArray())
            {
                hash = hash * 31 + b;
            }

            hash = hash * 31 + localDate.DayNumber;
            foreach (var c in category)
            {
                hash = hash * 31 + c;
            }

            return (int)((uint)hash % (uint)count);
        }
    }

    private static string Name(NotificationCandidateModel candidate) => Name(candidate.DisplayName);

    private static string Name(string? rawDisplayName)
    {
        var displayName = rawDisplayName?.Trim();
        if (string.IsNullOrEmpty(displayName))
        {
            return "bestie";
        }

        var firstSpace = displayName.IndexOf(' ');
        return firstSpace > 0 ? displayName[..firstSpace] : displayName;
    }
}
