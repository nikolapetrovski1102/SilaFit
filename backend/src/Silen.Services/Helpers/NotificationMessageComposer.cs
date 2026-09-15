using Silen.Common.Models;

namespace Silen.Services.Helpers;

/// <summary>A composed push message: what to say and which screen to open.</summary>
public sealed record NotificationContent(string Title, string Body, string Screen);

/// <summary>
/// Writes the actual push copy. Every category has several templates per
/// language register and the pick is stable per (user, UTC day, category), so
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
    public static NotificationContent GymReminder(NotificationCandidateModel candidate) =>
        Pick(candidate, NotificationCategories.GymReminder, "today",
            ("gym o'clock 🏋️", $"{Name(candidate)}, reservation for one at the squat rack. let's move."),
            ("your workout is waiting", $"{Name(candidate)}, the weights aren't gonna lift themselves."),
            ("bestie. gym. now.", "one session today = tomorrow-you saying ty. you in?"),
            ("quick ✅ for today", "sweat first, scroll later. your split is ready."),
            ("no excuses era 🚫", "even a short session counts. lock in for 30 minutes."),
            ("it's giving gym energy", "show up for the version of you that started this."),
            ("leg day said hi 👋", "your plan is loaded and waiting. let's get after it."));

    public static NotificationContent TrackSets(NotificationCandidateModel candidate, TimeSpan idle) =>
        Pick(candidate, NotificationCategories.TrackSets, "workout",
            ("log those sets 📝", "you've been quiet a minute — tap them in before your brain forgets."),
            ("sets > vibes", "don't leave them unlogged. your PRs need receipts."),
            ("quick one 🫡", "log the set, rest, repeat. future-you is watching."),
            ("don't ghost the log", $"{(int)idle.TotalMinutes} min since the last one. drop it in real quick."),
            ("receipts 📋", "unlogged sets don't count. keep the session honest."));

    public static NotificationContent TrackCalories(NotificationCandidateModel candidate) =>
        Pick(candidate, NotificationCategories.TrackCalories, "meals",
            ("calories check 🍽️", "what did you eat? 10 seconds now saves the guesswork."),
            ("food log looking a lil empty 👀", "log your meals so we can keep the plan honest."),
            ("no gatekeeping the plate", "drop today's food in and we'll do the math."),
            ("on track?", "log it and we'll tell you exactly where you stand vs your target."),
            ("don't lowball the log", "track it now so the numbers actually mean something."));

    public static NotificationContent MealIdea(NotificationCandidateModel candidate) =>
        Pick(candidate, NotificationCategories.MealIdea, "meals",
            ("dinner idea, zero stress 🍗", "high protein, low effort — peep the meal tab."),
            ("hungry + no plan = chaos", "we got meal ideas that fit your targets. take a look."),
            ("what's for dinner? 🧑‍🍳", "let us pick something that hits your protein goal."),
            ("meal inspo dropped", "fresh ideas that fit your macros. go grab one."),
            ("the fridge is empty, your excuses aren't", "we've got a meal for that. check the ideas."));

    public static NotificationContent Motivation(NotificationCandidateModel candidate) =>
        Pick(candidate, NotificationCategories.Motivation, "progress",
            ($"{candidate.WorkoutsLast7Days} sessions this week 🔥", "you're actually locked in. keep it rolling."),
            ("consistency > motivation", $"{candidate.WorkoutsLast7Days} workouts logged — that's the whole secret."),
            ("you're on a heater 🧊", $"{candidate.WorkoutsLast7Days} sessions this week. don't stop now."),
            ("look at you go", $"{candidate.WorkoutsLast7Days} workouts this week. the progress is real."),
            ("main character training arc", "showing up repeatedly is the flex. keep going."));

    public static NotificationContent Comeback(NotificationCandidateModel candidate) =>
        Pick(candidate, NotificationCategories.Comeback, "today",
            ("you made a rest, let's get back to the gym 💪", "your split missed you. one session to get back in rhythm."),
            ("rest day's over 👀", $"{Name(candidate)}, we saved your spot at the gym. come back stronger."),
            ("gym misses you, fr", "a quick session today resets everything. you got this."),
            ("we don't do ghosting here 👻", "come back and we'll pretend the break never happened."),
            ("back to it?", "one workout is all it takes to feel like you again."),
            ("round 2 starts now", "you've rested enough. let's get one in."));

    /// <summary>
    /// Monthly review upsell - non-paying users only. Points at the Progress tab
    /// where the locked AI review lives (the "screen" deep link the client routes on).
    /// </summary>
    public static NotificationContent MonthlyReviewUpsell(NotificationCandidateModel candidate) =>
        Pick(candidate, NotificationCategories.MonthlyReviewUpsell, "progress",
            ("your month, reviewed 🔍", "the AI review of your training is one unlock away. see what improved and what to fix."),
            ("the part your log can't explain", "your numbers are in. the coaching read on them is waiting in PRO."),
            ("monthly review is waiting", $"{Name(candidate)}, unlock PRO and get your full month read by your AI coach."),
            ("data in. verdict pending.", "you logged the month. unlock the review that tells you what to do with it."),
            ("what actually improved?", "your numbers know. unlock the full AI review and hear it."));

    private static NotificationContent Pick(
        NotificationCandidateModel candidate,
        string category,
        string screen,
        params (string Title, string Body)[] templates)
    {
        var index = StableIndex(candidate.UserId, DateOnly.FromDateTime(DateTime.UtcNow), category, templates.Length);
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

    private static string Name(NotificationCandidateModel candidate)
    {
        var displayName = candidate.DisplayName?.Trim();
        if (string.IsNullOrEmpty(displayName))
        {
            return "bestie";
        }

        var firstSpace = displayName.IndexOf(' ');
        return firstSpace > 0 ? displayName[..firstSpace] : displayName;
    }
}
