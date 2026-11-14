using Silen.Common.Localization;
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
///
/// Each category has English and Macedonian templates. The user's stored app
/// language (<see cref="NotificationCandidateModel.Language"/>) picks the set.
/// The two sets don't have to be the same length.
/// </summary>
public static class NotificationMessageComposer
{
    public static NotificationContent GymReminder(NotificationCandidateModel candidate, DateOnly localDate) =>
        Pick(candidate, localDate, NotificationCategories.GymReminder, "today",
        [
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
            ("your split entered the chat", "it brought sets, reps, and zero interest in excuses.")
        ],
        [
            ("време е за теретана 🏋️", $"{Name(candidate)}, те чека место на рекот за сквот. ајде да се движиме."),
            ("тренингот те чека", $"{Name(candidate)}, теговите нема сами да се кренат."),
            ("теретана. сега. 💪", "еден тренинг денес = утрешниот ти ќе ти каже фала. си внатре?"),
            ("брз ✅ за денес", "прво пот, па скролање. сплитот ти е спремен."),
            ("ера без изговори 🚫", "и краток тренинг се брои. фокус 30 минути."),
            ("денот за нозе вели здраво 👋", "планот е вчитан и те чека. ајде."),
            ("време за фокус 🔒", "дојде времето за тренинг. еден допир и си во движење."),
            ("докази > ветувања", "дојди, заврши ја работата, уживај во чувството после тренинг."),
            ("сплитот влезе во четот", "донесе серии, повторувања и нула интерес за изговори."),
        ]);

    public static NotificationContent TrackSets(NotificationCandidateModel candidate, TimeSpan idle, DateOnly localDate) =>
        Pick(candidate, localDate, NotificationCategories.TrackSets, "workout",
        [
            ("log those sets 📝", "you've been quiet a minute — tap them in before your brain forgets."),
            ("sets > vibes", "don't leave them unlogged. your PRs need receipts."),
            ("quick one 🫡", "log the set, rest, repeat. future-you is watching."),
            ("don't ghost the log", $"{(int)idle.TotalMinutes} min since the last one. drop it in real quick."),
            ("receipts 📋", "unlogged sets don't count. keep the session honest."),
            ("did the set even happen?", "no log, no lore. add the reps while they're fresh."),
            ("tiny admin moment", "tap in the set, then get back to being strong."),
            ("the log is on read", "give it the reps and weight. your progress chart deserves context."),
            ("document the damage 💪", "weights up? reps up? put it on the record.")
        ],
        [
            ("запиши ги сериите 📝", "малку си тивок — внеси ги пред да заборавиш."),
            ("серии > вајб", "не оставај ги незапишани. на рекордите им требаат докази."),
            ("брзо 🫡", "запиши серија, одмори, повтори. идниот ти гледа."),
            ("не го игнорирај дневникот", $"{(int)idle.TotalMinutes} мин од последната серија. внеси ја набрзина."),
            ("докази 📋", "незапишаните серии не се бројат. тренингот нека биде чесен."),
            ("дали серијата воопшто се случи?", "нема запис, нема приказна. внеси ги повторувањата додека се свежи."),
            ("документирај ја штетата 💪", "повеќе тежина? повеќе повторувања? запиши го."),
        ]);

    public static NotificationContent TrackCalories(NotificationCandidateModel candidate, DateOnly localDate) =>
        Pick(candidate, localDate, NotificationCategories.TrackCalories, "meals",
        [
            ("calories check 🍽️", "what did you eat? 10 seconds now saves the guesswork."),
            ("food log looking a lil empty 👀", "log your meals so we can keep the plan honest."),
            ("no gatekeeping the plate", "drop today's food in and we'll do the math."),
            ("on track?", "log it and we'll tell you exactly where you stand vs your target."),
            ("don't lowball the log", "track it now so the numbers actually mean something."),
            ("macro check, no judgment", "tell us what was on the plate. we'll handle the numbers."),
            ("your protein has receipts, right?", "log the meal and see where today's targets stand."),
            ("quick plate audit", "add what you ate before selective memory kicks in."),
            ("feed the data 🥣", "one fast log keeps your plan personal instead of guessy.")
        ],
        [
            ("проверка на калории 🍽️", "што јадеше? 10 секунди сега заштедуваат погодување."),
            ("дневникот за храна е малку празен 👀", "внеси ги оброците за планот да остане чесен."),
            ("на вистинскиот пат?", "внеси го и ќе ти кажеме точно каде си во однос на целта."),
            ("макро проверка, без осудување", "кажи ни што имаше во чинијата. ние ќе ги средиме бројките."),
            ("брза ревизија на чинијата", "додај што јадеше пред селективната меморија да проработи."),
            ("нахрани ги податоците 🥣", "еден брз внес го држи планот личен, а не на погодување."),
        ]);

    public static NotificationContent MealIdea(NotificationCandidateModel candidate, DateOnly localDate) =>
        Pick(candidate, localDate, NotificationCategories.MealIdea, "meals",
        [
            ("dinner idea, zero stress 🍗", "high protein, low effort — peep the meal tab."),
            ("hungry + no plan = chaos", "we got meal ideas that fit your targets. take a look."),
            ("what's for dinner? 🧑‍🍳", "let us pick something that hits your protein goal."),
            ("meal inspo dropped", "fresh ideas that fit your macros. go grab one."),
            ("the fridge is empty, your excuses aren't", "we've got a meal for that. check the ideas."),
            ("protein, but make it good", "your next meal can hit the target without tasting like homework."),
            ("dinner side quest unlocked", "pick a meal that fits the plan and still passes the vibe check."),
            ("your macros ordered room service", "the meal ideas are ready. sadly, you still have to cook."),
            ("less scrolling, more seasoning", "we found a meal that fits. go make something elite.")
        ],
        [
            ("идеја за вечера, нула стрес 🍗", "многу протеини, малку труд — види во табот за оброци."),
            ("гладен + без план = хаос", "имаме идеи за оброци што ги погодуваат твоите цели. погледни."),
            ("што има за вечера? 🧑‍🍳", "дозволи ни да избереме нешто што ја погодува целта за протеини."),
            ("стигна инспирација за оброци", "свежи идеи што одговараат на твоите макроа. земи една."),
            ("протеини, ама вкусно", "следниот оброк може да ја погоди целта без да има вкус на домашна задача."),
            ("помалку скролање, повеќе зачини", "најдовме оброк што се вклопува. направи нешто врвно."),
        ]);

    public static NotificationContent Motivation(NotificationCandidateModel candidate, DateOnly localDate) =>
        Pick(candidate, localDate, NotificationCategories.Motivation, "progress",
        [
            ($"{candidate.WorkoutsLast7Days} sessions this week 🔥", "you're actually locked in. keep it rolling."),
            ("consistency > motivation", $"{candidate.WorkoutsLast7Days} workouts logged — that's the whole secret."),
            ("you're on a heater 🧊", $"{candidate.WorkoutsLast7Days} sessions this week. don't stop now."),
            ("look at you go", $"{candidate.WorkoutsLast7Days} workouts this week. the progress is real."),
            ("main character training arc", "showing up repeatedly is the flex. keep going."),
            ("the streak is streaking", $"{candidate.WorkoutsLast7Days} sessions down. momentum looks good on you."),
            ("quietly becoming unstoppable", "no big speech. just more proof that consistency works."),
            ("plot armor: consistency", "you keep showing up and the numbers keep moving. funny how that works."),
            ("okay athlete 👀", "your week is looking strong. keep the standard where it is.")
        ],
        [
            ($"тренинзи оваа недела: {candidate.WorkoutsLast7Days} 🔥", "навистина си фокусиран. продолжи така."),
            ("доследност > мотивација", $"внесени тренинзи: {candidate.WorkoutsLast7Days} — тоа е целата тајна."),
            ("во серија си 🧊", $"тренинзи оваа недела: {candidate.WorkoutsLast7Days}. не застанувај сега."),
            ("гледај те само", "неделава ти изгледа силно. напредокот е вистински."),
            ("тренинг арка на главниот лик", "тоа што постојано се појавуваш е најголемиот флекс. продолжи."),
            ("тивко стануваш незапирлив", "без големи говори. само уште еден доказ дека доследноста работи."),
            ("океј, атлетичару 👀", "неделата ти изгледа силно. задржи го стандардот."),
        ]);

    public static NotificationContent Comeback(NotificationCandidateModel candidate, DateOnly localDate) =>
        Pick(candidate, localDate, NotificationCategories.Comeback, "today",
        [
            ("you made a rest, let's get back to the gym 💪", "your split missed you. one session to get back in rhythm."),
            ("rest day's over 👀", $"{Name(candidate)}, we saved your spot at the gym. come back stronger."),
            ("gym misses you, fr", "a quick session today resets everything. you got this."),
            ("we don't do ghosting here 👻", "come back and we'll pretend the break never happened."),
            ("back to it?", "one workout is all it takes to feel like you again."),
            ("round 2 starts now", "you've rested enough. let's get one in."),
            ("the comeback arc starts here", "nothing dramatic. just open the plan and do the first exercise."),
            ("still got it, btw", "take the smallest win: show up, warm up, see what happens."),
            ("your routine wants a reboot", "one session today and we're officially back."),
            ("no guilt, just reps", "the break happened. cool. now let's build the next streak.")
        ],
        [
            ("одмори доволно, ајде назад во теретана 💪", "сплитот ти недостига. еден тренинг за да се вратиш во ритам."),
            ("денот за одмор заврши 👀", $"{Name(candidate)}, ти го чуваме местото во теретана. врати се посилен."),
            ("теретаната те чека, сериозно", "еден брз тренинг денес враќа сè. можеш ти тоа."),
            ("тука не исчезнуваме без збор 👻", "врати се и ќе се правиме дека паузата никогаш не се случила."),
            ("назад на работа?", "само еден тренинг треба за пак да се чувствуваш свој."),
            ("рунда 2 почнува сега", "доволно одмараше. ајде еден тренинг."),
            ("без вина, само повторувања", "паузата се случи. океј. сега да ја градиме следната серија."),
        ]);

    /// <summary>
    /// Monthly review upsell - non-paying users only. Points at the Progress tab
    /// where the locked AI review lives (the "screen" deep link the client routes on).
    /// </summary>
    public static NotificationContent MonthlyReviewUpsell(NotificationCandidateModel candidate, DateOnly localDate) =>
        Pick(candidate, localDate, NotificationCategories.MonthlyReviewUpsell, "progress",
        [
            ("your month, reviewed 🔍", "the AI review of your training is one unlock away. see what improved and what to fix."),
            ("the part your log can't explain", "your numbers are in. the coaching read on them is waiting in PRO."),
            ("monthly review is waiting", $"{Name(candidate)}, unlock PRO and get your full month read by your AI coach."),
            ("data in. verdict pending.", "you logged the month. unlock the review that tells you what to do with it."),
            ("what actually improved?", "your numbers know. unlock the full AI review and hear it."),
            ("your training lore, decoded", "unlock the AI read on what worked, what stalled, and what's next."),
            ("the month has receipts", "your full progress breakdown is ready in PRO. go see the plot.")
        ],
        [
            ("твојот месец, прегледан 🔍", "AI прегледот на твоите тренинзи е на едно отклучување. види што се подобри и што да поправиш."),
            ("месечниот преглед те чека", $"{Name(candidate)}, отклучи PRO и добиј целосен преглед на месецот од твојот AI тренер."),
            ("податоците се тука. пресудата чека.", "го внесе месецот. отклучи го прегледот што ти кажува што понатаму."),
            ("што навистина се подобри?", "бројките знаат. отклучи го целосниот AI преглед и дознај."),
            ("месецот има докази", "целосната анализа на напредокот те чека во PRO."),
        ]);

    /// <summary>
    /// Sunday "your AI plan is ready" push - sent directly by
    /// WeeklyPlanGenerationService for one user at a time, outside the
    /// candidate-scanning pipeline the other categories go through, so this
    /// takes a bare userId/displayName rather than a full
    /// <see cref="NotificationCandidateModel"/>. Points at "splits" (My
    /// Splits), where the freshly generated split - and a link into the new
    /// diet plan - both land.
    /// </summary>
    public static NotificationContent WeeklyAiPlanReady(
        Guid userId, string? displayName, bool splitKept = false, string language = AppText.English)
    {
        var macedonian = AppText.Normalize(language) == AppText.Macedonian;
        var templates = (splitKept, macedonian) switch
        {
            (true, true) => WeeklyAiPlanReadyKeptSplitTemplatesMk,
            (true, false) => WeeklyAiPlanReadyKeptSplitTemplates,
            (false, true) => WeeklyAiPlanReadyTemplatesMk,
            _ => WeeklyAiPlanReadyTemplates,
        };
        var index = StableIndex(userId, DateOnly.FromDateTime(DateTime.UtcNow), NotificationCategories.WeeklyAiPlanReady, templates.Length);
        var (title, body) = templates[index];
        return new NotificationContent(title, body.Replace("{name}", Name(displayName, AppText.Normalize(language))), "splits");
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

    private static readonly (string Title, string Body)[] WeeklyAiPlanReadyTemplatesMk =
    [
        ("твојата недела, испланирана 🗓️", "{name}, твојот AI сплит и план за исхрана за оваа недела се спремни. погледни."),
        ("стигна свеж план", "{name}, нов сплит и план за оброци направени од минатонеделниот дневник. види ги."),
        ("оваа недела, средена ✅", "AI тренерот ги направи тренинзите и исхраната за следната недела. во Мои сплитови е."),
        ("направено од твоите податоци 📊", "минатонеделните тренинзи станаа план за оваа недела. види го."),
        ("тренерот зготви 🔥", "свежиот сплит и план за оброци се активни. отвори Мои сплитови и види што следи."),
    ];

    private static readonly (string Title, string Body)[] WeeklyAiPlanReadyKeptSplitTemplatesMk =
    [
        ("оброците за неделава се спремни 🍽️", "{name}, сплитот веќе изгледаше добро, па го задржавме. планот за оброци и листата за купување се спремни."),
        ("сплитот останува, оброците се нови", "{name}, нема промени во тренинзите оваа недела. новиот план за оброци те чека."),
        ("исти сплит, свежо мени", "твојот план за тренинг сè уште е во ред. оброците за неделава се спремни."),
        ("ако се вклопува, го чуваме", "{name}, сплитот останува. планот за оброци и листата за купување се освежени."),
    ];

    /// <summary>A trainer assigned a split / diet plan (<paramref name="documentOnly"/> false) or shared
    /// one of its PDFs. Names the program, so it is built directly rather than from a rotating template.</summary>
    public static NotificationContent TrainerProgramAssigned(
        bool isSplit, string programName, string? trainerName, bool documentOnly, string language = AppText.English)
    {
        var macedonian = AppText.Normalize(language) == AppText.Macedonian;
        var trainer = string.IsNullOrWhiteSpace(trainerName)
            ? (macedonian ? "твојот тренер" : "your trainer")
            : trainerName.Trim();
        var screen = isSplit ? "splits" : "meals";
        var program = programName.Length > 60 ? programName[..57] + "..." : programName;

        if (macedonian)
        {
            if (documentOnly)
            {
                return new NotificationContent(
                    "нов документ од тренерот 📄",
                    $"{trainer} сподели документ за {program}. ти испративме и безбеден линк на е-пошта.",
                    screen);
            }

            return isSplit
                ? new NotificationContent("нов сплит од тренерот 💪", $"{trainer} ти додели {program}. отвори го и почни.", screen)
                : new NotificationContent("нов план за исхрана од тренерот 🍽️", $"{trainer} ти додели {program}. оброците те чекаат.", screen);
        }

        if (documentOnly)
        {
            return new NotificationContent(
                "new document from your trainer 📄",
                $"{trainer} shared a document for {program}. we emailed you a secure link too.",
                screen);
        }

        return isSplit
            ? new NotificationContent("new split from your trainer 💪", $"{trainer} assigned you {program}. open it and get started.", screen)
            : new NotificationContent("new diet plan from your trainer 🍽️", $"{trainer} assigned you {program}. your meals are ready to view.", screen);
    }

    private static NotificationContent Pick(
        NotificationCandidateModel candidate,
        DateOnly localDate,
        string category,
        string screen,
        (string Title, string Body)[] english,
        (string Title, string Body)[] macedonian)
    {
        var templates = candidate.Language == AppText.Macedonian ? macedonian : english;
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

    private static string Name(NotificationCandidateModel candidate) => Name(candidate.DisplayName, candidate.Language);

    private static string Name(string? rawDisplayName, string language)
    {
        var displayName = rawDisplayName?.Trim();
        if (string.IsNullOrEmpty(displayName))
        {
            return language == AppText.Macedonian ? "шампионе" : "bestie";
        }

        var firstSpace = displayName.IndexOf(' ');
        return firstSpace > 0 ? displayName[..firstSpace] : displayName;
    }
}
