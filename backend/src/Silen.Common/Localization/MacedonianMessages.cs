namespace Silen.Common.Localization;

/// <summary>
/// Macedonian text for the API's user-facing messages, keyed by the exact
/// English text the code throws or returns. Copy follows the app: informal
/// "ти", "сплит", "план за исхрана", "Надгради", "Поставки". Pro and Advanced
/// stay as plan names.
///
/// When you add or change a user message in code, add or update its entry
/// here. A missing entry just shows the English text.
///
/// Admin-console and partner-API messages are left out on purpose: those
/// callers are English-only.
/// </summary>
internal static class MacedonianMessages
{
    public static readonly IReadOnlyDictionary<string, string> Exact = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        // Generic fallbacks and exception defaults
        ["Something went wrong"] = "Нешто тргна наопаку",
        ["Please check the information you entered and try again."] = "Провери ги внесените податоци и обиди се пак.",
        ["Too many requests. Please try again later."] = "Премногу барања. Обиди се пак подоцна.",
        ["Too many attempts. Please try again later."] = "Премногу обиди. Обиди се пак подоцна.",
        ["We couldn't find what you were looking for."] = "Не го најдовме тоа што го бараш.",
        ["You need to sign in to do that."] = "Треба да се најавиш за да го направиш тоа.",
        ["Upgrade to Pro to unlock AI insights."] = "Надгради на Pro за да ги отклучиш AI увидите.",
        ["Upgrade to Advanced to unlock your weekly AI overview."] = "Надгради на Advanced за да го отклучиш неделниот AI преглед.",
        ["Allow AI data sharing in Settings to use AI features."] = "Дозволи споделување податоци со AI во Поставки за да ги користиш AI функциите.",
        ["Create a free account to unlock this feature."] = "Направи бесплатна сметка за да ја отклучиш оваа функција.",
        ["Your role does not allow that."] = "Твојата улога не го дозволува тоа.",
        ["Not enough activity logged this month yet for an AI review."] = "Овој месец сè уште нема доволно внесена активност за AI преглед.",
        ["You've reached your plan's limit. Upgrade to add more."] = "Го достигна ограничувањето на твојот план. Надгради за да додадеш повеќе.",

        // Profile and onboarding
        ["We couldn't find your profile."] = "Не го најдовме твојот профил.",
        ["Choose between 1 and 7 training days."] = "Избери помеѓу 1 и 7 дена за тренинг.",
        ["Choose a workout duration between 15 and 180 minutes."] = "Избери времетраење на тренингот помеѓу 15 и 180 минути.",
        ["Choose a valid training experience option."] = "Избери валидно тренинг искуство.",
        ["Choose a valid equipment access option."] = "Избери валиден пристап до опрема.",
        ["Choose a valid daily activity option."] = "Избери валидна дневна активност.",
        ["Choose a valid gender option."] = "Избери валиден пол.",
        ["Choose a valid goal."] = "Избери валидна цел.",
        ["Enter an age between 13 and 100."] = "Внеси возраст помеѓу 13 и 100.",
        ["Enter a valid height."] = "Внеси валидна висина.",
        ["Enter a valid weight."] = "Внеси валидна тежина.",
        ["Enter a valid bodyweight."] = "Внеси валидна телесна тежина.",
        ["Enter a valid daily calorie target."] = "Внеси валидна дневна цел за калории.",

        // Settings
        ["We couldn't find your settings."] = "Не ги најдовме твоите поставки.",
        ["Choose kg or lb."] = "Избери kg или lb.",
        ["Choose km or mi."] = "Избери km или mi.",
        ["Choose dark, light, or device."] = "Избери темна, светла или според уредот.",
        ["Choose Male or Female."] = "Избери машки или женски.",
        ["Choose a reminder time between 00:00 and 23:59."] = "Избери време за потсетник помеѓу 00:00 и 23:59.",
        ["Choose a valid timezone for your workout reminder."] = "Избери валидна временска зона за потсетникот за тренинг.",
        ["Enter a valid daily water target."] = "Внеси валидна дневна цел за вода.",
        ["We couldn't recognize your timezone."] = "Не ја препознавме твојата временска зона.",
        ["That push token is not valid."] = "Тој токен за известувања не е валиден.",
        ["Unknown platform."] = "Непозната платформа.",

        // Account and sign-in
        ["A device id is required."] = "Потребен е ID на уредот.",
        ["Email and password are required."] = "Потребни се е-пошта и лозинка.",
        ["That verification session has expired. Please start again."] = "Таа сесија за потврда истече. Почни одново.",
        ["That code has expired. Please request a new one."] = "Кодот истече. Побарај нов.",
        ["Too many incorrect attempts. Please request a new code."] = "Премногу погрешни обиди. Побарај нов код.",
        ["That code isn't right. Please try again."] = "Кодот не е точен. Обиди се пак.",
        ["Please wait a moment before requesting another code."] = "Почекај малку пред да побараш нов код.",
        ["Invalid email or password."] = "Погрешна е-пошта или лозинка.",
        ["We couldn't verify your Google sign-in."] = "Не можевме да ја потврдиме најавата со Google.",
        ["We couldn't verify your Apple sign-in."] = "Не можевме да ја потврдиме најавата со Apple.",
        ["Your session has expired. Please sign in again."] = "Сесијата ти истече. Најави се повторно.",
        ["An account already exists with this email. Sign in with its original method, then link this provider from Settings."] =
            "Веќе постои сметка со оваа е-пошта. Најави се на првобитниот начин, па поврзи го овој начин на најава од Поставки.",
        ["Add an email to your account before requesting a data export."] = "Додај е-пошта на сметката пред да побараш извоз на податоци.",

        // Splits and exercises
        ["That split couldn't be found."] = "Тој сплит не е пронајден.",
        ["That split couldn't be activated."] = "Тој сплит не можеше да се активира.",
        ["Give the split a name."] = "Дај му име на сплитот.",
        ["Duration must be between 1 and 14 days."] = "Времетраењето мора да биде помеѓу 1 и 14 дена.",
        ["AI-generated splits aren't included in your plan. Upgrade to unlock them."] = "Сплитовите направени со AI не се дел од твојот план. Надгради за да ги отклучиш.",
        ["Upgrade to Pro to duplicate splits."] = "Надгради на Pro за да дуплираш сплитови.",
        ["Upgrade to Pro to browse suggested splits."] = "Надгради на Pro за да прелистуваш предложени сплитови.",
        ["You've reached your plan's limit on saved splits. Upgrade to add more."] = "Го достигна ограничувањето на зачувани сплитови за твојот план. Надгради за да додадеш повеќе.",
        ["Give the day a title."] = "Дај му наслов на денот.",
        ["Day index must be 1 or greater."] = "Редниот број на денот мора да биде 1 или поголем.",
        ["Target sets must be at least 1."] = "Целните серии мора да бидат најмалку 1.",
        ["The rep range must start at 1 or higher and the high end must not be below the low end."] =
            "Опсегот на повторувања мора да почнува од 1 или повеќе, а горната граница не смее да биде под долната.",
        ["Give the exercise a name."] = "Дај му име на вежбата.",
        ["Pick the muscle group it trains."] = "Избери ја мускулната група што ја тренира.",
        ["Pick the equipment it uses."] = "Избери ја опремата што ја користи.",
        ["Say whether it's a compound or isolation movement."] = "Наведи дали е сложено или изолирано движење.",

        // Workouts and progress
        ["Enter how long the workout took."] = "Внеси колку траеше тренингот.",
        ["That workout session couldn't be found."] = "Тој тренинг не е пронајден.",
        ["You've used today's free unlocks. Get Pro for unlimited Progress."] = "Ги искористи денешните бесплатни отклучувања. Земи Pro за неограничен Напредок.",
        ["Upgrade to Pro to track progress for each exercise."] = "Надгради на Pro за да го следиш напредокот за секоја вежба.",
        ["Month must be between 1 and 12."] = "Месецот мора да биде помеѓу 1 и 12.",
        ["Week must be between 1 and 53."] = "Неделата мора да биде помеѓу 1 и 53.",
        ["That's not a valid month."] = "Тоа не е валиден месец.",
        ["Log a bit more this week - workouts and meals - and your weekly review will unlock."] =
            "Внеси уште малку оваа недела - тренинзи и оброци - и неделниот преглед ќе се отклучи.",
        ["Log a bit more this month - workouts and meals - and your review will unlock."] =
            "Внеси уште малку овој месец - тренинзи и оброци - и прегледот ќе се отклучи.",

        // AI
        ["AI insights are temporarily unavailable."] = "AI увидите привремено не се достапни.",
        ["AI insights are temporarily unavailable. Please try again shortly."] = "AI увидите привремено не се достапни. Обиди се пак наскоро.",
        ["AI plan generation is temporarily unavailable."] = "Правењето планови со AI привремено не е достапно.",

        // Diet plans and meals
        ["That diet plan couldn't be found."] = "Тој план за исхрана не е пронајден.",
        ["Give the plan a name."] = "Дај му име на планот.",
        ["Duration must be between 1 and 31 days."] = "Времетраењето мора да биде помеѓу 1 и 31 ден.",
        ["AI-generated diet plans aren't included in your plan. Upgrade to unlock them."] = "Плановите за исхрана направени со AI не се дел од твојот план. Надгради за да ги отклучиш.",
        ["You've reached your plan's limit on saved diet plans. Upgrade to add more."] = "Го достигна ограничувањето на зачувани планови за исхрана за твојот план. Надгради за да додадеш повеќе.",
        ["Upgrade to Pro to browse diet plans."] = "Надгради на Pro за да прелистуваш планови за исхрана.",
        ["Upgrade to Pro to create and follow diet plans."] = "Надгради на Pro за да правиш и следиш планови за исхрана.",
        ["Choose a meal first."] = "Прво избери оброк.",
        ["Give the meal a name."] = "Дај му име на оброкот.",
        ["Add at least one ingredient."] = "Додај барем една состојка.",
        ["Choose a valid meal type."] = "Избери валиден вид оброк.",
        ["That meal status isn't valid."] = "Тој статус на оброкот не е валиден.",
        ["Every food needs a name."] = "Секоја намирница треба да има име.",
        ["Macros can't be negative."] = "Макроата не можат да бидат негативни.",
        ["That meal is no longer available."] = "Тој оброк повеќе не е достапен.",
        ["That diet guide couldn't be found."] = "Тој водич за исхрана не е пронајден.",

        // Foods
        ["Give the food a name."] = "Дај ѝ име на намирницата.",
        ["That name is too long."] = "Тоа име е предолго.",
        ["Nutrition values can't be negative."] = "Хранливите вредности не можат да бидат негативни.",
        ["Calories can't exceed 900 per 100 g."] = "Калориите не можат да бидат над 900 на 100 g.",
        ["Macros can't add up to more than 100 g per 100 g."] = "Макроата заедно не можат да бидат повеќе од 100 g на 100 g.",
        ["Check the sodium and serving size."] = "Провери ги натриумот и големината на порцијата.",
        ["Enter at least calories or one macro."] = "Внеси барем калории или едно макро.",
        ["Enter an amount greater than zero."] = "Внеси количина поголема од нула.",

        // Meal scan and link imports
        ["Upgrade to Advanced to scan meals with AI."] = "Надгради на Advanced за да скенираш оброци со AI.",
        ["Choose a JPEG, PNG or WebP photo."] = "Избери JPEG, PNG или WebP фотографија.",
        ["That photo is too large. Try another one."] = "Фотографијата е преголема. Пробај со друга.",
        ["Choose a photo of your meal."] = "Избери фотографија од твојот оброк.",
        ["Couldn't read that photo right now. Your scan wasn't used - try again."] = "Не можевме да ја прочитаме фотографијата сега. Скенирањето не ти е потрошено - обиди се пак.",
        ["Share a TikTok video link to import it."] = "Сподели линк од TikTok видео за да го увезеш.",
        ["Couldn't open that video. It may be private or removed."] = "Не можевме да го отвориме видеото. Можеби е приватно или избришано.",
        ["Couldn't read that video right now. Your scan wasn't used - try again."] = "Не можевме да го прочитаме видеото сега. Скенирањето не ти е потрошено - обиди се пак.",
        ["Meal imports are part of Advanced. Pro includes workout imports."] = "Увозот на оброци е дел од Advanced. Pro вклучува увоз на тренинзи.",

        // Images and documents
        ["Choose an image to upload."] = "Избери слика за прикачување.",
        ["Only JPG, PNG and WEBP images are accepted."] = "Се прифаќаат само JPG, PNG и WEBP слики.",
        ["That file isn't a valid PDF."] = "Таа датотека не е валиден PDF.",
        ["That Word document couldn't be converted. Export it as PDF and upload that instead."] = "Тој Word документ не можеше да се претвори. Извези го како PDF и прикачи го тој.",
        ["Only PDF and Word (.docx, .doc) documents are accepted."] = "Се прифаќаат само PDF и Word (.docx, .doc) документи.",
        ["That document couldn't be read. If it's password-protected, remove the password and upload it again."] =
            "Документот не можеше да се прочита. Ако е заштитен со лозинка, отстрани ја и прикачи го повторно.",
        ["Word conversion isn't available right now. Export the document as PDF and upload that instead."] = "Претворањето Word документи сега не е достапно. Извези го документот како PDF и прикачи го тој.",
        ["That Word document took too long to convert. Export it as PDF and upload that instead."] = "Претворањето на Word документот траеше предолго. Извези го како PDF и прикачи го тој.",
        ["That client no longer has this document."] = "Тој клиент повеќе го нема овој документ.",
        ["This document is no longer shared with you."] = "Овој документ повеќе не е споделен со тебе.",
        ["That document no longer exists."] = "Тој документ повеќе не постои.",

        // Purchases and promo codes
        ["We couldn't verify that purchase."] = "Не можевме да го потврдиме тоа плаќање.",
        ["That purchase doesn't match a known plan."] = "Тоа плаќање не одговара на ниту еден познат план.",
        ["We couldn't verify that purchase with Apple."] = "Не можевме да го потврдиме плаќањето со Apple.",
        ["We couldn't verify that purchase with Google Play."] = "Не можевме да го потврдиме плаќањето со Google Play.",
        ["This subscription is linked to a different Silen account. Sign in with that account to use it."] =
            "Оваа претплата е поврзана со друга сметка. Најави се со таа сметка за да ја користиш.",
        ["That purchase isn't currently active."] = "Тоа плаќање моментално не е активно.",
        ["Choose a monthly or yearly plan."] = "Избери месечен или годишен план.",
        ["Enter the code exactly as you received it."] = "Внеси го кодот точно како што го доби.",
        ["This code has expired."] = "Овој код истече.",
        ["This code isn't active yet."] = "Овој код сè уште не е активен.",
        ["Codes are for new members - this account has already had a subscription."] = "Кодовите се за нови членови - оваа сметка веќе имала претплата.",
        ["This code has already been fully claimed."] = "Овој код е веќе целосно искористен.",
        ["That code isn't valid."] = "Тој код не е валиден.",

        // Support and contact forms
        ["Please choose a topic."] = "Избери тема.",
        ["Please enter your name."] = "Внеси го твоето име.",
        ["Please keep your name under 100 characters."] = "Името нека биде пократко од 100 знаци.",
        ["Please enter your email address."] = "Внеси ја твојата е-пошта.",
        ["Please enter a valid email address."] = "Внеси валидна е-пошта.",
        ["Please describe what happened."] = "Опиши што се случи.",
        ["Please write between 10 and 5,000 characters."] = "Напиши помеѓу 10 и 5.000 знаци.",
    };

    /// <summary>Messages with a value in them. More specific patterns go first:
    /// the first one that matches wins.</summary>
    public static readonly IReadOnlyList<(string English, string Macedonian)> Templates =
    [
        ("Keep the meal name under {0} characters.", "Името на оброкот нека биде пократко од {0} знаци."),
        ("A meal can have up to {0} ingredients.", "Оброкот може да има најмногу {0} состојки."),
        ("A meal can hold up to {0} foods.", "Оброкот може да содржи најмногу {0} намирници."),
        ("Enter an amount between 1 and {0} g.", "Внеси количина помеѓу 1 и {0} g."),
        ("That image is too large - the limit is {0}MB.", "Сликата е преголема - ограничувањето е {0} MB."),
        ("The file must be under {0} MB.", "Датотеката мора да биде помала од {0} MB."),
        ("You've used all {0} scans for today. They reset at midnight.", "Ги искористи сите {0} скенирања за денес. Се обновуваат на полноќ."),
        ("You've used all your imports for today. You get {0} workout and {1} meal imports a day - they reset at midnight.",
            "Ги искористи сите увози за денес. Добиваш {0} увози на тренинзи и {1} увози на оброци дневно - се обновуваат на полноќ."),
        ("You've used your {0} free imports. Upgrade to Pro for {1} workout imports a day, or Advanced to import meals too.",
            "Ги искористи твоите {0} бесплатни увози. Надгради на Pro за {1} увози на тренинзи дневно или на Advanced за да увезуваш и оброци."),
        ("You've used all {0} workout imports for today. They reset at midnight.", "Ги искористи сите {0} увози на тренинзи за денес. Се обновуваат на полноќ."),
        ("You've used all {0} meal imports for today. They reset at midnight.", "Ги искористи сите {0} увози на оброци за денес. Се обновуваат на полноќ."),
        ("You can request a data export once every {0} days. Next available on {1}.",
            "Можеш да побараш извоз на податоци еднаш на секои {0} дена. Следниот е достапен на {1}."),
    ];
}
