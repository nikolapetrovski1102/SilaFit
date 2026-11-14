#!/usr/bin/env python3
"""Builds the Macedonian marketing site (website/mk/) from the English pages.

The English HTML stays the source: each page is copied, its text swapped for
the Macedonian below (every phrase must still be found, so an English edit
that breaks a translation fails loudly), asset paths pointed one folder up,
and both versions get the EN/MK switch and hreflang links.

Run after changing an English page:  python3 tools/build_mk_site.py
Privacy and terms stay English only; the MK footer marks them (EN).
Dynamic text (pricing, meals, form messages) is localized in the scripts,
keyed on <html lang="mk">.
"""
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

SITE = Path(__file__).resolve().parent.parent / 'website'
OUT = SITE / 'mk'
ORIGIN = 'https://sila.fitness'

PAGES = ['index', 'features', 'training', 'nutrition', 'pricing', 'about',
         'download', 'support', 'press', 'careers', 'delete-account']
EN_ONLY = ['privacy', 'terms']

# Public URL of each English page (download.html is served at /download).
def en_url(page):
    return {'index': '/', 'download': '/download'}.get(page, f'/{page}.html')

def mk_url(page):
    return '/mk/' if page == 'index' else f'/mk/{page}.html'

# ---------------------------------------------------------------- shared chrome
COMMON = [
    ('aria-label="Switch to light mode" title="Switch to light mode"',
     'aria-label="Префрли на светла тема" title="Префрли на светла тема"'),
    ('aria-label="Switch color theme" title="Switch color theme"',
     'aria-label="Смени тема" title="Смени тема"'),
    ('aria-label="Menu"', 'aria-label="Мени"'),
    ('alt="SilaFit logo"', 'alt="Лого на SilaFit"'),
    ('>Get the app</a>', '>Преземи</a>'),
    ('>Features</a>', '>Функции</a>'),
    ('>Training</a>', '>Тренинг</a>'),
    ('>Nutrition</a>', '>Исхрана</a>'),
    ('>Pricing</a>', '>Цени</a>'),
    ('<p>Workout tracking, training splits, and meal plans in one app, with streaks that respect recovery.</p>',
     '<p>Следење тренинзи, сплитови и планови за исхрана во една апликација, со низа што го почитува опоравокот.</p>'),
    ('<h4>Product</h4>', '<h4>Производ</h4>'),
    ('<h4>Company</h4>', '<h4>Компанија</h4>'),
    ('<h4>Legal</h4>', '<h4>Правно</h4>'),
    ('>Download the app</a>', '>Преземи ја апликацијата</a>'),
    ('>Meal planning</a>', '>Планирање оброци</a>'),
    ('Training splits', 'Сплитови за тренинг'),
    ('>About</a>', '>За нас</a>'),
    ('>Community</a>', '>Заедница</a>'),
    ('>Support</a>', '>Поддршка</a>'),
    ('>Careers</a>', '>Кариера</a>'),
    ('>Press kit</a>', '>За медиуми</a>'),
    ('>Privacy policy</a>', '>Политика за приватност (EN)</a>'),
    ('>Terms of service</a>', '>Услови за користење (EN)</a>'),
    ('>Delete my account</a>', '>Избриши го мојот профил</a>'),
    ('>Press</a>', '>Медиуми</a>'),
    ('>Privacy</a>', '>Приватност (EN)</a>'),
    ('>Contact us</a>', '>Контактирај нè</a>'),
    ('>Media contact</a>', '>Контакт за медиуми</a>'),
    ('>Get in touch</a>', '>Пиши ни</a>'),
    ('>Request deletion</a>', '>Побарај бришење</a>'),
    ('© 2026 SilaFit. All rights reserved.', '© 2026 SilaFit. Сите права задржани.'),
    ('Made for lifters, by lifters.', 'Направено од вежбачи, за вежбачи.'),
    ('aria-label="Download SilaFit on the App Store"', 'aria-label="Преземи SilaFit од App Store"'),
    ('<small>Download on the</small>', '<small>Преземи од</small>'),
    ('<span class="eyebrow">Keep exploring</span>', '<span class="eyebrow">Истражи понатаму</span>'),
    ('Sila, the SilaFit ram mascot', 'Сила, овенот маскота на SilaFit'),
    ('>Privacy Policy</a>.', '>Политика за приватност</a> (на англиски).'),
]

# ---------------------------------------------------------------- pages
PAGE_TEXT = {
'index': [
    ('<title>SilaFit — Workout Tracker &amp; Meal Plans for Lifters</title>',
     '<title>SilaFit — Следење тренинзи и планови за исхрана</title>'),
    ('content="SilaFit — Workout Tracker &amp; Meal Plans for Lifters"',
     'content="SilaFit — Следење тренинзи и планови за исхрана"'),
    ('content="Log every set, follow a proven training split, and eat to your goal. SilaFit pairs workout tracking and PR progress with meal plans, macro tracking, and AI food scan. Free on iPhone."',
     'content="Запиши ја секоја серија, следи проверен сплит и јади според својата цел. SilaFit ги спојува следењето тренинзи и личните рекорди со планови за исхрана, следење макроа и AI скенирање храна. Бесплатно на iPhone."'),
    ('content="Train smarter. Eat right. Recover better. Workout tracking, training splits, and meal plans in one app."',
     'content="Тренирај попаметно. Јади правилно. Опорави се подобро. Следење тренинзи, сплитови и планови за исхрана во една апликација."'),
    ('>Workout + nutrition tracking<', '>Тренинг + исхрана<'),
    ('Strength, measured <em>to the rep.</em>', 'Сила, мерена <em>до секое повторување.</em>'),
    ('Log every set, follow a proven split, and eat to your goal. Workout tracking, PR progress, meal plans, and macros in one app.',
     'Запиши ја секоја серија, следи проверен сплит и јади според својата цел. Тренинзи, лични рекорди, планови за исхрана и макроа во една апликација.'),
    ('Free on iPhone · Android coming soon', 'Бесплатно на iPhone · Android наскоро'),
    ('>See the app</a>', '>Погледни ја апликацијата</a>'),
    ('alt="Lifter pressing dumbbells overhead"', 'alt="Вежбач крева дамбели над глава"'),
    ('<small>New PR</small><b>Bench · 100 kg</b>', '<small>Нов рекорд</small><b>Бенч · 100 kg</b>'),
    ('<small>Set 3 of 4</small><b>80 kg × 8 reps</b>', '<small>Серија 3 од 4</small><b>80 kg × 8 повт.</b>'),
    ('<small>Rest</small>', '<small>Одмор</small>'),
    ('Current streak', 'Тековна низа'),
    ('<span class="t-muted-inline"> d</span>', '<span class="t-muted-inline"> дена</span>'),
    ('aria-label="This week: 6 of 7 days done, including one rest day"',
     'aria-label="Оваа недела: 6 од 7 дена, вклучувајќи еден ден за одмор"'),
    ('<li class="is-done">M</li><li class="is-done">T</li><li class="is-rest">W</li><li class="is-done">T</li><li class="is-done">F</li><li class="is-done">S</li><li class="is-today">S</li>',
     '<li class="is-done">П</li><li class="is-done">В</li><li class="is-rest">С</li><li class="is-done">Ч</li><li class="is-done">П</li><li class="is-done">С</li><li class="is-today">Н</li>'),
    ('Rest days count. Recovery is training too.', 'Деновите за одмор се бројат. И опоравокот е тренинг.'),
    ('Exercises in the library', 'Вежби во библиотеката'),
    ('Ready-made training splits', 'Готови сплитови за тренинг'),
    ('Whole-food meal recipes', 'Рецепти од вистинска храна'),
    ('>Inside the app<', '>Во апликацијата<'),
    ('Built for the gym floor, not the spreadsheet.', 'Направено за теретана, не за табели.'),
    ('aria-label="App screenshots"', 'aria-label="Слики од апликацијата"'),
    ("alt=\"Today screen with the week strip, today's Push session and your active split\" /><span>Today</span>",
     'alt="Екранот „Денес“ со неделата, денешниот Push тренинг и активниот сплит" /><span>Денес</span>'),
    ('alt="Logging a set of dumbbell incline bench press: weight, reps and rest timer" /><span>Set logging</span>',
     'alt="Запишување серија косо потиснување со дамбели: тежина, повторувања и тајмер за одмор" /><span>Запишување серии</span>'),
    ('alt="Progress screen with the estimated 1RM trend for wide-grip lat pulldown" /><span>Progress &amp; PRs</span>',
     'alt="Екранот за напредок со проценетиот 1RM за влечење на скрипец со широк зафат" /><span>Напредок и рекорди</span>'),
    ("alt=\"Nutrition screen with calories left, macros and today's meals from your diet plan\" /><span>Nutrition</span>",
     'alt="Екранот за исхрана со преостанатите калории, макроата и денешните оброци од планот" /><span>Исхрана</span>'),
    ('alt="My Splits: create a split or pick one matched to your goal, level and schedule" /><span>Splits</span>',
     'alt="Мои сплитови: направи сплит или избери еден според цел, ниво и распоред" /><span>Сплитови</span>'),
    ('alt="Home screen: training, nutrition and progress in one app" /><span>All in one</span>',
     'alt="Почетен екран: тренинг, исхрана и напредок во една апликација" /><span>Сè на едно место</span>'),
    ('Your next PR is already on the curve.', 'Твојот следен рекорд е веќе на кривата.'),
    ('one more rep. then the next PR.', 'уште едно повторување. па следниот рекорд.'),
    ('Free forever tier. No card required.', 'Бесплатен пакет засекогаш. Без картичка.'),
    ('Scan with your phone camera to download', 'Скенирај со камерата на телефонот за да ја преземеш'),
],
'features': [
    ('Features — SilaFit', 'Функции — SilaFit'),
    ('content="Workout splits, 1RM and PR tracking, adaptive meal plans, streaks, AI monthly reports and AI food scan: everything SilaFit tracks for lifters."',
     'content="Сплитови, следење 1RM и лични рекорди, прилагодливи планови за исхрана, низи, месечни AI извештаи и AI скенирање храна: сè што SilaFit следи за вежбачите."'),
    ('>The system<', '>Системот<'),
    ("Everything a lifter tracks. Nothing they don't.", 'Сè што вежбачот следи. Ништо повеќе.'),
    ('>Smart workout splits<', '>Паметни сплитови<'),
    ('A curated split library (PPL, Upper/Lower, PHUL, Arnold) matched to your goal, with session tracking down to the set.',
     'Избрана библиотека сплитови (PPL, Upper/Lower, PHUL, Arnold) според твојата цел, со следење на секој тренинг до последната серија.'),
    ('>1RM progression &amp; PR tracking<', '>Напредок на 1RM и лични рекорди<'),
    ('Per-exercise charts of estimated 1RM, top set and volume, with every personal record flagged the moment you hit it.',
     'Графикони по вежба за проценет 1RM, најдобра серија и волумен, а секој личен рекорд се означува во моментот кога ќе го постигнеш.'),
    ('>Adaptive meal planning<', '>Прилагодливо планирање оброци<'),
    ('Calorie and macro targets calibrated to your training load, with whole-food meal suggestions built from USDA data.',
     'Цели за калории и макроа прилагодени на твоите тренинзи, со предлози за оброци од вистинска храна врз основа на USDA податоци.'),
    ('>Streaks that stick<', '>Низа што трае<'),
    ('A streak engine that celebrates consistency, and counts rest days, because recovery is training too.',
     'Низа што ја слави доследноста и ги брои деновите за одмор, зашто и опоравокот е тренинг.'),
    ('>Bodyweight check-ins<', '>Мерење телесна тежина<'),
    ('Morning weigh-ins logged in two taps, trended against your training volume.',
     'Утринско мерење запишано со два допири, споредено со волуменот на тренинзите.'),
    ('>AI monthly analytics<', '>Месечна AI анализа<'),
    ('A coach-grade report every month: volume landmarks, deload signals, and exactly what to change next block.',
     'Секој месец извештај како од тренер: волумен, сигнали за deload и што точно да смениш во следниот циклус.'),
    ('>AI food scan<', '>AI скенирање храна<'),
    ('Snap a photo of your plate and get an estimated calorie and macro breakdown, ready to log. Or search the food database by name.',
     'Сликај ја чинијата и добиј проценка на калориите и макроата, подготвена за запишување. Или пребарај ја базата на храна по име.'),
    ('>Your exercises, your meals<', '>Твои вежби, твои оброци<'),
    ("Add custom exercises and recipes when the library doesn't have yours, and build a diet plan around them with a step-by-step wizard.",
     'Додај свои вежби и рецепти кога ги нема во библиотеката и направи план за исхрана околу нив, чекор по чекор.'),
    ('>How it works<', '>Како функционира<'),
    ('From first rep to next PR.', 'Од првото повторување до следниот рекорд.'),
    ('<h3>Pick your split</h3>', '<h3>Избери сплит</h3>'),
    ('Choose a proven program or build your own. Your weekly schedule is set instantly.',
     'Избери проверена програма или направи своја. Неделниот распоред е готов веднаш.'),
    ('<h3>Log every set</h3>', '<h3>Запиши ја секоја серија</h3>'),
    ('Track weight and reps as you lift. Your 1RM and PR curve update in real time.',
     'Запишувај тежина и повторувања додека тренираш. 1RM и рекордите се ажурираат во живо.'),
    ('<h3>Fuel with precision</h3>', '<h3>Јади прецизно</h3>'),
    ('A weekly meal plan calibrated to your training volume. Whole foods, no guessing.',
     'Неделен план за исхрана прилагоден на волуменот на тренинзите. Вистинска храна, без погодување.'),
    ('<h3>Read the AI report</h3>', '<h3>Прочитај го AI извештајот</h3>'),
    ('Every month: peak volume, deload signals, and your next training block.',
     'Секој месец: највисок волумен, сигнали за deload и твојот следен циклус.'),
],
'training': [
    ('content="Proven training splits (PPL, Upper/Lower, PHUL, Arnold) matched to your goal, with an estimated 1RM and PR curve from every logged set."',
     'content="Проверени сплитови (PPL, Upper/Lower, PHUL, Arnold) според твојата цел, со проценет 1RM и крива на рекорди од секоја запишана серија."'),
    ('alt="Lifter chalking up before a deadlift"', 'alt="Вежбач става магнезиум пред мртво кревање"'),
    ('>Training library<', '>Библиотека на тренинзи<'),
    ('A split for every goal.', 'Сплит за секоја цел.'),
    ('Pick a proven program or build your own. SilaFit sets your weekly schedule and session targets instantly.',
     'Избери проверена програма или направи своја. SilaFit веднаш ти ги поставува неделниот распоред и целите за секој тренинг.'),
    ('>PPL Hypertrophy<', '>PPL хипертрофија<'),
    ('Intermediate · 6 days · Build muscle', 'Средно ниво · 6 дена · Мускулна маса'),
    ('Beginner · 4 days · Stay active', 'Почетник · 4 дена · Активен живот'),
    ('>5-Day Metabolic Circuit<', '>Метаболичко коло, 5 дена<'),
    ('Beginner · 5 days · Lose fat', 'Почетник · 5 дена · Губење маснотии'),
    ('Advanced · 6 days · Build muscle', 'Напредно · 6 дена · Мускулна маса'),
    ('>PHUL Power-Hypertrophy<', '>PHUL сила и хипертрофија<'),
    ('Intermediate · 4 days · Strength &amp; size', 'Средно ниво · 4 дена · Сила и маса'),
    ('plain-list__tag">Popular<', 'plain-list__tag">Популарен<'),
    ('plain-list__tag">New<', 'plain-list__tag">Нов<'),
    ('reveal">Progress</span>', 'reveal">Напредок</span>'),
    ('Every set moves the curve.', 'Секоја серија ја поместува кривата.'),
    ('Deadlift · estimated 1RM', 'Мртво кревање · проценет 1RM'),
    ('</i>Logged</span>', '</i>Запишано</span>'),
    ('</i>New PR</span>', '</i>Нов рекорд</span>'),
    ('A sample 12-week block. SilaFit charts your estimated 1RM from every logged set and flags each new PR.',
     'Пример циклус од 12 недели. SilaFit го црта проценетиот 1RM од секоја запишана серија и го означува секој нов рекорд.'),
    ('Nutrition &amp; meal plans', 'Исхрана и планови за оброци'),
],
'nutrition': [
    ('Nutrition &amp; meal plans', 'Исхрана и планови за оброци'),
    ('content="Calorie and macro targets that follow your training, whole-food meal plans built from USDA data, and AI food scan."',
     'content="Цели за калории и макроа што ги следат тренинзите, планови за оброци од вистинска храна врз USDA податоци и AI скенирање храна."'),
    ('reveal">Nutrition</span>', 'reveal">Исхрана</span>'),
    ('Meal plans that flex with your training.', 'Планови за исхрана што се прилагодуваат на тренинзите.'),
    ('Whole foods at realistic portions, with macros summed from per-100g USDA data, not guessed. Pick a goal, get a week, log it in one tap.',
     'Вистинска храна во реални порции, со макроа пресметани од USDA податоци на 100 g, без погодување. Избери цел, добиј план за недела, запиши со еден допир.'),
    ('data-count="2000">2,000<', 'data-count="2000">2.000<'),
    ('Daily kcal target', 'Дневна цел kcal'),
    ('1,640 logged today', '1.640 запишани денес'),
    ('<span class="eyebrow">Protein</span>', '<span class="eyebrow">Протеини</span>'),
    ('<span class="eyebrow">Carbs</span>', '<span class="eyebrow">Јаглехидрати</span>'),
    ('<span class="eyebrow">Fats</span>', '<span class="eyebrow">Масти</span>'),
    ('g logged</span>', 'g запишани</span>'),
    ('Suggested this month', 'Предлози за овој месец'),
    ('Refreshed monthly', 'Се обновува секој месец'),
    ('>Pricing<svg', '>Цени<svg'),
],
'pricing': [
    ('Pricing — SilaFit', 'Цени — SilaFit'),
    ('content="Start free on iPhone and upgrade inside the app when you need more. Monthly or yearly plans, cancel anytime."',
     'content="Започни бесплатно на iPhone и надгради во апликацијата кога ќе ти треба повеќе. Месечни или годишни пакети, откажи кога сакаш."'),
    ('reveal">Pricing</span>', 'reveal">Цени</span>'),
    ('Start free. Upgrade when the numbers demand it.', 'Започни бесплатно. Надгради кога бројките ќе побараат.'),
    ('aria-label="Billing period"', 'aria-label="Период на плаќање"'),
    ('>Monthly</button>', '>Месечно</button>'),
    ('>Yearly <span', '>Годишно <span'),
    ('Start on Free, then upgrade inside the app. Subscriptions are billed through the App Store and you can cancel anytime from your Apple ID settings.',
     'Започни со бесплатниот пакет, а потоа надгради во апликацијата. Претплатите се наплаќаат преку App Store и можеш да ги откажеш во секое време од поставките на Apple ID.'),
    ('reveal">Community</span>', 'reveal">Заедница</span>'),
    ('Deadlift · 180 kg PR', 'Мртво кревање · рекорд 180 kg'),
    ('“Watching my estimated 1RM climb every week kept me honest. Finished the block with a 180 kg deadlift.”',
     '„Гледајќи како проценетиот 1RM ми расте секоја недела, останав доследен. Циклусот го завршив со 180 kg мртво кревање.“'),
    ('Advanced tier · Powerlifting block', 'Advanced пакет · Пауерлифтинг циклус'),
    ('Lean Cut · 2,000 kcal', 'Lean Cut · 2.000 kcal'),
    ('“The meal plans are actual food I already cook. I stopped tracking in three apps and just follow the week.”',
     '„Плановите за исхрана се вистинска храна што веќе ја готвам. Престанав да следам во три апликации и само ја следам неделата.“'),
    ('Pro tier · Lean Cut plan', 'Pro пакет · Lean Cut план'),
    ('First strict pull-up · 6 weeks', 'Прво чисто згибање · 6 недели'),
    ('“Started on the free tier. Six weeks later I did my first strict pull-up. The mascot celebrates harder than my gym buddies.”',
     '„Почнав со бесплатниот пакет. По шест недели го направив првото чисто згибање. Маскотата слави повеќе од другарите во теретана.“'),
    ('Free tier · Calisthenics', 'Бесплатен пакет · Калистеника'),
],
'about': [
    ('About SilaFit', 'За SilaFit'),
    ('content="SilaFit builds precision kinetic fitness tracking — AI-assisted splits, adaptive nutrition, and streaks that respect recovery."',
     'content="SilaFit гради прецизно следење на тренинзите: сплитови со помош на AI, прилагодлива исхрана и низи што го почитуваат опоравокот."'),
    ('Built for lifters who track everything.', 'Направено за вежбачи што следат сè.'),
    ('SilaFit exists because most fitness apps make you choose between good workout tracking and good nutrition tracking. We built the one that does both, and ties them together.',
     'SilaFit постои затоа што повеќето фитнес апликации те тераат да избираш помеѓу добро следење тренинзи и добро следење исхрана. Ние направивме апликација што ги прави двете и ги поврзува.'),
    ('<h2>Why we built it</h2>', '<h2>Зошто ја направивме</h2>'),
    ("Training and nutrition aren't separate problems — your macro targets should move with your training load, and your training decisions should account for recovery. SilaFit's Precision Kinetic system was built around that link: workout telemetry and adaptive meal planning in one dashboard, instead of juggling a training app, a food log, and a spreadsheet.",
     'Тренингот и исхраната не се одделни проблеми: целите за макроа треба да се менуваат со оптоварувањето на тренинзите, а одлуките за тренингот треба да го земат предвид опоравокот. Системот Precision Kinetic на SilaFit е изграден околу таа врска: статистика од тренинзите и прилагодливо планирање оброци на едно место, наместо да жонглираш со апликација за тренинг, дневник за храна и табела.'),
    ('<h2>What we care about</h2>', '<h2>Што ни е важно</h2>'),
    ('<strong>Accuracy over guesswork.</strong> Macro targets are calculated from real per-100g nutrition data, not rounded estimates.',
     '<strong>Точност наместо погодување.</strong> Целите за макроа се пресметуваат од вистински нутритивни податоци на 100 g, не од заокружени проценки.'),
    ('<strong>Respect for recovery.</strong> Rest days and deload signals count as progress, not gaps in a streak.',
     '<strong>Почит кон опоравокот.</strong> Деновите за одмор и deload се бројат како напредок, не како прекин на низата.'),
    ("<strong>Your data is yours.</strong> We don't sell personal information or use it for third-party advertising — see our ",
     '<strong>Твоите податоци се твои.</strong> Не продаваме лични податоци и не ги користиме за рекламирање од трети страни. Види ја нашата '),
    ('<h2>Get in touch</h2>', '<h2>Контакт</h2>'),
    ("Questions, feedback, or a story you're working on? Reach us at ",
     'Прашања, повратни информации или пишуваш приказна? Пиши ни на '),
    ('</a>, or visit <a class="legal-link" href="support.html">Support</a> and our <a class="legal-link" href="press.html">Press kit</a>.',
     '</a>, или посети ја <a class="legal-link" href="support.html">Поддршката</a> и <a class="legal-link" href="press.html">материјалите за медиуми</a>.'),
],
'download': [
    ('Download SilaFit', 'Преземи SilaFit'),
    ('content="Get SilaFit, the workout tracker, training split and meal planning app. Free on iPhone, coming soon to Android."',
     'content="Преземи SilaFit, апликацијата за следење тренинзи, сплитови и планирање оброци. Бесплатна на iPhone, наскоро на Android."'),
    ('content="Train smarter. Eat right. Recover better. Free on iPhone."',
     'content="Тренирај попаметно. Јади правилно. Опорави се подобро. Бесплатно на iPhone."'),
    ('Opening <span data-handoff-store>the App Store</span>', 'Се отвора <span data-handoff-store>App Store</span>'),
    ('Get SilaFit, free to start', 'SilaFit, бесплатно за почеток'),
    ('Not opening? Tap here', 'Не се отвора? Допри тука'),
    ('eyebrow--accent">Download</div>', 'eyebrow--accent">Преземи</div>'),
    ('Get SilaFit.', 'Преземи SilaFit.'),
    ('Log every set, follow a proven split, and eat to your goal. Free to start, no card required.',
     'Запиши ја секоја серија, следи проверен сплит и јади според својата цел. Бесплатно за почеток, без картичка.'),
    ('aria-label="SilaFit on Google Play, coming soon"', 'aria-label="SilaFit на Google Play, наскоро"'),
    ('Coming soon to', 'Наскоро на'),
    ('Free on iPhone · Android coming soon', 'Бесплатно на iPhone · Android наскоро'),
    ('Scan with your phone camera to get the app', 'Скенирај со камерата на телефонот за да ја преземеш апликацијата'),
],
'support': [
    ('<title>SilaFit Support</title>', '<title>Поддршка за SilaFit</title>'),
    ('content="Get help with your SilaFit account, workouts, meal planning, notifications, and subscriptions."',
     'content="Помош за твојот SilaFit профил, тренинзи, планирање оброци, известувања и претплати."'),
    ('>SilaFit support<', '>Поддршка за SilaFit<'),
    ('How can we help?', 'Како можеме да помогнеме?'),
    ('Questions about your account, training plan, nutrition targets, workout history, reminders, or subscription? Send us the details and we’ll help you get moving again.',
     'Прашања за профилот, планот за тренинг, целите за исхрана, историјата на тренинзи, потсетниците или претплатата? Прати ни детали и ќе ти помогнеме да продолжиш.'),
    ('<h2>Send us a message</h2>', '<h2>Прати ни порака</h2>'),
    ('>Name</label>', '>Име</label>'),
    ('>Email</label>', '>Е-пошта</label>'),
    ('<legend>Topic</legend>', '<legend>Тема</legend>'),
    ('<span>Account &amp; sign-in</span>', '<span>Профил и најава</span>'),
    ('<span>Training &amp; splits</span>', '<span>Тренинг и сплитови</span>'),
    ('<span>Nutrition &amp; meals</span>', '<span>Исхрана и оброци</span>'),
    ('<span>Subscription &amp; billing</span>', '<span>Претплата и плаќање</span>'),
    ('<span>Bug report</span>', '<span>Пријави грешка</span>'),
    ('<span>Something else</span>', '<span>Нешто друго</span>'),
    ('>Message</label>', '>Порака</label>'),
    ('placeholder="What happened, and what did you expect? Your device model, iOS version and SilaFit version help us a lot."',
     'placeholder="Што се случи и што очекуваше? Моделот на уредот, верзијата на iOS и верзијата на SilaFit многу ни помагаат."'),
    ('</span> / 5,000</span>', '</span> / 5.000</span>'),
    ('<span class="contact-form__label">Send message</span>', '<span class="contact-form__label">Испрати порака</span>'),
    ("We usually reply within one business day. Please don't include passwords or payment details.",
     'Обично одговараме во рок од еден работен ден. Не праќај лозинки или податоци за плаќање.'),
    ('<h3>Message sent.</h3>', '<h3>Пораката е испратена.</h3>'),
    ("Thanks, we've got it. We'll reply to ", 'Благодариме, ја добивме. Ќе ти одговориме на '),
    (', usually within one business day.', ', обично во рок од еден работен ден.'),
    ('>Send another message</button>', '>Испрати друга порака</button>'),
    ('<h2>Prefer email?</h2>', '<h2>Повеќе сакаш е-пошта?</h2>'),
    ('<p>Write to ', '<p>Пиши на '),
    ('. Include your device model, iOS version, SilaFit version, and a short description of what happened.',
     '. Наведи го моделот на уредот, верзијата на iOS и SilaFit и кратко опиши што се случи.'),
    ('<h2>Privacy requests</h2>', '<h2>Барања за приватност</h2>'),
    ('For access, correction, deletion, or other privacy requests, email ',
     'За пристап, исправка, бришење или други барања за приватност, пиши на '),
    (' from the address associated with your account.', ' од адресата поврзана со твојот профил.'),
    ('<h2>Common questions</h2>', '<h2>Чести прашања</h2>'),
    ('<h3>I can’t sign in</h3>', '<h3>Не можам да се најавам</h3>'),
    ('Confirm that you are using the same sign-in method you used when creating the account. For email sign-in, check that your address is correct and request a new verification code if the previous one expired.',
     'Провери дали го користиш истиот начин на најава како кога го направи профилот. За најава со е-пошта, провери дали адресата е точна и побарај нов код за потврда ако претходниот истекол.'),
    ('<h3>My workout did not sync</h3>', '<h3>Тренингот не се синхронизираше</h3>'),
    ('Keep SilaFit open with an internet connection and retry. An in-progress workout is saved on your device so you can continue after briefly leaving the app.',
     'Држи ја SilaFit отворена со интернет врска и обиди се повторно. Тренингот во тек се чува на уредот, па можеш да продолжиш и откако накратко ќе ја напуштиш апликацијата.'),
    ('<h3>I’m not receiving reminders</h3>', '<h3>Не добивам потсетници</h3>'),
    ('In SilaFit, open Settings and make sure Workout reminders are enabled. Then confirm that notifications are allowed for SilaFit in iOS Settings.',
     'Во SilaFit отвори Поставки и провери дали се вклучени потсетниците за тренинг. Потоа провери дали известувањата за SilaFit се дозволени во поставките на iOS.'),
    ('<h3>How do I request account or data deletion?</h3>', '<h3>Како да побарам бришење на профилот или податоците?</h3>'),
    ('You can delete your account and all associated data directly from the app under Settings → Delete account, or use our ',
     'Профилот и сите поврзани податоци можеш да ги избришеш директно во апликацијата, во Поставки → Избриши профил, или преку нашата '),
    (">account deletion page</a> if you'd rather request it by email.",
     '>страница за бришење профил</a> ако сакаш да побараш по е-пошта.'),
    ('<h2>Before emailing us</h2>', '<h2>Пред да ни пишеш</h2>'),
    ('Please do not send passwords, verification codes, payment-card details, or other secrets. Screenshots are helpful, but review them first and hide information you do not want to share.',
     'Не праќај лозинки, кодови за потврда, податоци од платежни картички или други тајни. Сликите од екранот помагаат, но прво прегледај ги и скриј ги информациите што не сакаш да ги споделиш.'),
],
'press': [
    ('<title>SilaFit Press Kit</title>', '<title>SilaFit за медиуми</title>'),
    ('content="SilaFit brand assets, boilerplate description, and media contact."',
     'content="Бренд материјали, краток опис и контакт за медиуми на SilaFit."'),
    ('eyebrow--accent">Press kit</div>', 'eyebrow--accent">За медиуми</div>'),
    ('Brand assets & boilerplate.', 'Бренд материјали и опис.'),
    ('Logos, icons, and a short description for anyone writing about SilaFit.',
     'Логоа, икони и краток опис за сите што пишуваат за SilaFit.'),
    ('<h2>Boilerplate</h2>', '<h2>Краток опис</h2>'),
    ('SilaFit is a Precision Kinetic fitness app pairing workout telemetry with adaptive meal planning — AI-assisted training splits, estimated 1RM progress charts, bodyweight tracking, and nutrition targets that adjust to training load.',
     'SilaFit е фитнес апликација што ги спојува статистиката од тренинзите и прилагодливото планирање оброци: сплитови со помош на AI, графикони за напредокот на проценетиот 1RM, следење телесна тежина и цели за исхрана што се прилагодуваат на оптоварувањето.'),
    ('<h2>Logo & app icon</h2>', '<h2>Лого и икона</h2>'),
    ("Right-click (or long-press) any asset below to save it. Please don't alter the mark's shape or colors.",
     'Кликни со десното копче (или држи подолго) на материјалот за да го зачуваш. Те молиме не ги менувај формата и боите на знакот.'),
    ('alt="SilaFit app icon"', 'alt="Икона на апликацијата SilaFit"'),
    ('<span>App icon</span>', '<span>Икона на апликацијата</span>'),
    ('alt="SilaFit mark in lime, transparent background"', 'alt="Знакот на SilaFit во лиме боја, проѕирна позадина"'),
    ('<span>Mark for dark backgrounds</span>', '<span>Знак за темни позадини</span>'),
    ('alt="SilaFit mark in burgundy, transparent background"', 'alt="Знакот на SilaFit во бордо боја, проѕирна позадина"'),
    ('<span>Mark for light backgrounds</span>', '<span>Знак за светли позадини</span>'),
    ('Sila, the SilaFit ram mascot, standing', 'Сила, овенот маскота на SilaFit, стои'),
    ('<span>Sila, standing</span>', '<span>Сила, стои</span>'),
    ('Sila, the SilaFit ram mascot, charging', 'Сила, овенот маскота на SilaFit, во залет'),
    ('<span>Sila, charging</span>', '<span>Сила, во залет</span>'),
    ('<h2>Media contact</h2>', '<h2>Контакт за медиуми</h2>'),
    ('For interviews, screenshots, or anything else, reach us at ',
     'За интервјуа, слики од екранот или нешто друго, пишете ни на '),
],
'careers': [
    ('Careers at SilaFit', 'Кариера во SilaFit'),
    ('content="Open roles and how to reach the SilaFit team about working with us."',
     'content="Отворени позиции и како да го контактираш тимот на SilaFit за работа."'),
    ('eyebrow--accent">Careers</div>', 'eyebrow--accent">Кариера</div>'),
    ("We're not hiring right now.", 'Моментално не вработуваме.'),
    ("SilaFit is a small team, and we don't have open roles at the moment. That changes — if you'd like to be considered when it does, send us a note.",
     'SilaFit е мал тим и во моментов немаме отворени позиции. Тоа ќе се смени, па ако сакаш да те земеме предвид кога ќе се отвори нешто, пиши ни.'),
    ('<h2>Stay in touch</h2>', '<h2>Остани во контакт</h2>'),
    ("Tell us what you do and what you're interested in at ", 'Кажи ни што работиш и што те интересира на '),
    ('. We keep an eye on it and reach out when something relevant opens up.',
     '. Ја следиме оваа адреса и ќе ти се јавиме кога ќе се отвори нешто соодветно.'),
    ('<h2>What we build</h2>', '<h2>Што градиме</h2>'),
    ('Read more about the product and what drives it on our ', 'Прочитај повеќе за производот и што нè води на '),
    ('>About page</a>.', '>страницата За нас</a>.'),
],
'delete-account': [
    ('Delete Your SilaFit Account', 'Избриши го SilaFit профилот'),
    ('content="How to permanently delete your SilaFit account and all associated data, in the app or by request."',
     'content="Како трајно да го избришеш SilaFit профилот и сите поврзани податоци, во апликацијата или по барање."'),
    ('eyebrow--accent">Account</div>', 'eyebrow--accent">Профил</div>'),
    ('>Delete your account</h1>', '>Избриши го профилот</h1>'),
    ("You're always in control of your data. Delete your SilaFit account and everything tied to it — workouts, meal logs, progress history, and profile — permanently and at any time.",
     'Секогаш ги контролираш своите податоци. Избриши го SilaFit профилот и сè што е поврзано со него (тренинзи, запишани оброци, историја на напредок и профил), трајно и во секое време.'),
    ('<h2>Option 1 — In the app</h2>', '<h2>Опција 1: Во апликацијата</h2>'),
    ('The fastest way. Open SilaFit, go to <strong>Settings → Account → Delete account</strong>, confirm, and your account and all associated data are permanently deleted right away.',
     'Најбрзиот начин. Отвори ја SilaFit, оди во <strong>Поставки → Профил → Избриши профил</strong>, потврди, и профилот со сите поврзани податоци веднаш трајно се брише.'),
    ('<h2>Option 2 — By request</h2>', '<h2>Опција 2: По барање</h2>'),
    ("Can't access the app? Email us and we'll delete your account for you.",
     'Немаш пристап до апликацијата? Пиши ни и ние ќе го избришеме профилот.'),
    ('>Email privacy@sila.fitness</a>', '>Пиши на privacy@sila.fitness</a>'),
    ('<h2>What gets deleted</h2>', '<h2>Што се брише</h2>'),
    ("Deleting your account permanently removes your profile, authentication credentials, workout and split history, session logs, meal plans and nutrition logs, hydration and bodyweight entries, streaks, notification preferences, and subscription status from SilaFit's systems.",
     'Бришењето на профилот трајно ги отстранува од системите на SilaFit твојот профил, податоците за најава, историјата на тренинзи и сплитови, запишаните тренинзи, плановите за исхрана и запишаните оброци, внесовите за вода и телесна тежина, низите, поставките за известувања и статусот на претплатата.'),
    ('Some information may be retained for a limited period where required for fraud prevention, security, dispute resolution, or legal and accounting obligations, as described in our ',
     'Некои информации може да се чуваат ограничено време кога тоа е потребно за спречување измами, безбедност, решавање спорови или законски и сметководствени обврски, како што е опишано во нашата '),
    ('<h2>Before you go</h2>', '<h2>Пред да заминеш</h2>'),
    ('Account deletion cannot be undone. If you have an active subscription, cancel it separately through the App Store or your payment provider — deleting your SilaFit account does not automatically cancel billing.',
     'Бришењето на профилот не може да се врати. Ако имаш активна претплата, откажи ја посебно преку App Store или давателот на плаќање, бидејќи бришењето на SilaFit профилот не ја откажува автоматски наплатата.'),
    ("If you'd rather keep your data but stop using SilaFit, you can simply sign out; your account and data stay intact until you choose to delete it.",
     'Ако сакаш да ги задржиш податоците, а да престанеш да ја користиш SilaFit, само одјави се. Профилот и податоците остануваат недопрени додека не одлучиш да го избришеш.'),
    ('<h2>Need help?</h2>', '<h2>Ти треба помош?</h2>'),
    ('If you run into any issues requesting deletion, contact ', 'Ако имаш проблем со барањето за бришење, пиши на '),
    ('</a> or visit <a class="legal-link" href="support.html">SilaFit Support</a>. We may ask you to verify account ownership before completing a request made by email.',
     '</a> или посети ја <a class="legal-link" href="support.html">Поддршката на SilaFit</a>. Може да побараме да потврдиш дека профилот е твој пред да го извршиме барањето добиено по е-пошта.'),
],
}

# ---------------------------------------------------------------- helpers
def replace_all(html, pairs, page, where):
    for en, mk in pairs:
        if en not in html:
            sys.exit(f'{page}.html: {where} phrase not found (English changed?):\n  {en}')
        html = html.replace(en, mk)
    return html


def switch_link(href, lang, label, aria):
    return (f'<a class="lang-switch" href="{href}" hreflang="{lang}" lang="{lang}" '
            f'aria-label="{aria}">{label}</a>\n        ')


def alternates(page):
    en, mk = ORIGIN + en_url(page), ORIGIN + mk_url(page)
    return (f'<link rel="alternate" hreflang="en" href="{en}" />\n'
            f'  <link rel="alternate" hreflang="mk" href="{mk}" />\n'
            f'  <link rel="alternate" hreflang="x-default" href="{en}" />\n  ')


THEME_BUTTON = '<button class="theme-toggle"'


def add_chrome(html, page, mk):
    """hreflang links before the canonical, the language switch before the
    theme button. Idempotent, so the English pages can be patched in place."""
    if 'hreflang="mk"' not in html:
        html = html.replace('<link rel="canonical"', alternates(page) + '<link rel="canonical"', 1)
    if 'class="lang-switch"' not in html:
        if THEME_BUTTON not in html:
            sys.exit(f'{page}.html: no theme button to put the language switch beside')
        if mk:
            href = '../download' if page == 'download' else ('../' if page == 'index' else f'../{page}.html')
            link = switch_link(href, 'en', 'EN', 'English')
        else:
            href = 'mk/' if page == 'index' else f'mk/{page}.html'
            link = switch_link(href, 'mk', 'MK', 'Македонски')
        html = html.replace(THEME_BUTTON, link + THEME_BUTTON, 1)
    return html


def localize_paths(html, page):
    # Shared assets live one folder up; the inline loader scripts build paths too.
    html = re.sub(r'((?:src|href)=")(css|js|assets)/', r'\1../\2/', html)
    html = html.replace("= 'assets/img/branding/loader_'", "= '../assets/img/branding/loader_'")
    for legal in EN_ONLY:
        html = html.replace(f'href="{legal}.html"', f'href="../{legal}.html"')
    html = html.replace('href="/download"', 'href="download.html"')
    # Canonical and og:url point at the Macedonian address.
    own = ORIGIN + en_url(page)
    html = html.replace(f'<link rel="canonical" href="{own}" />',
                        f'<link rel="canonical" href="{ORIGIN + mk_url(page)}" />')
    html = html.replace(f'<meta property="og:url" content="{own}" />',
                        f'<meta property="og:url" content="{ORIGIN + mk_url(page)}" />')
    html = html.replace('<html lang="en">', '<html lang="mk" data-root="../">', 1)
    if 'lang="mk"' not in html:
        sys.exit(f'{page}.html: no <html lang="en"> to switch')
    html = html.replace('<meta property="og:type"', '<meta property="og:locale" content="mk_MK" />\n  <meta property="og:type"', 1)
    return html


class TextScan(HTMLParser):
    """Collects visible text and alt/aria/title/placeholder values still in
    Latin script, so an untranslated phrase is easy to spot."""
    KEEP = re.compile(r'^[\s\d.,·×+−%€/:()\-–—&;|@]*$')
    ALLOWED = {'SilaFit', 'App Store', 'Google Play', 'iPhone', 'Android', 'kg', 'g', 'kcal', 'AI',
               'PPL', 'Upper / Lower', 'Arnold Split', 'Lean Cut', 'Pro', 'Advanced', 'Website', 'EN', 'MK',
               'English', 'Marko P.', 'Elena R.', 'Ivana K.', 'USDA', '1RM', 'deload', 'Precision Kinetic', 'Push', 'iOS', 'Apple ID'}

    def __init__(self):
        super().__init__()
        self.found, self.skip = [], 0

    def handle_starttag(self, tag, attrs):
        if tag in ('script', 'style', 'svg'):
            self.skip += 1
        for k, v in attrs:
            if k in ('alt', 'aria-label', 'title', 'placeholder') and v or (k == 'content' and dict(attrs).get('name', dict(attrs).get('property', '')) in ('description', 'og:title', 'og:description', 'twitter:title', 'twitter:description') and v):
                self.check(v)

    def handle_endtag(self, tag):
        if tag in ('script', 'style', 'svg'):
            self.skip -= 1

    def handle_data(self, data):
        if not self.skip:
            self.check(data)

    def check(self, text):
        rest = text
        for word in sorted(self.ALLOWED, key=len, reverse=True):
            rest = rest.replace(word, '')
        rest = re.sub(r'\S+@\S+|https?://\S+|\S+\.(?:png|svg|webp)\S*', '', rest)
        if re.search(r'[A-Za-z]{3,}', rest) and not re.search(r'[А-Яа-яЃЌЉЊЏЅЈѓќљњџѕј]', text):
            self.found.append(text.strip())


def main():
    OUT.mkdir(exist_ok=True)
    leftovers = {}
    for page in PAGES:
        src = SITE / f'{page}.html'
        en = src.read_text(encoding='utf-8')

        patched = add_chrome(en, page, mk=False)
        if patched != en:
            src.write_text(patched, encoding='utf-8')
            en = patched

        html = replace_all(en, PAGE_TEXT.get(page, []), page, 'page')
        html = replace_all(html, [p for p in COMMON if p[0] in html], page, 'common')
        html = localize_paths(html, page)
        html = re.sub(r'<a class="lang-switch"[^>]*>MK</a>\n\s*', '', html)
        html = add_chrome(html, page, mk=True)
        (OUT / f'{page}.html').write_text(html, encoding='utf-8')

        scan = TextScan()
        scan.feed(html)
        if scan.found:
            leftovers[page] = scan.found

    print(f'Wrote {len(PAGES)} pages to {OUT.relative_to(SITE.parent)}/')
    for page, found in leftovers.items():
        print(f'\n{page}.html, still Latin text:')
        for text in found:
            print('  ·', text[:140])


if __name__ == '__main__':
    main()
