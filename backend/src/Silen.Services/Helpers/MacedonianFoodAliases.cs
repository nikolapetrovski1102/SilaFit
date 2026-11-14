using System.Text.RegularExpressions;

namespace Silen.Services.Helpers;

/// <summary>
/// Lets a Macedonian user search the (English) food catalog in Macedonian:
/// "пилешки гради" becomes "chicken breast", "јајца" becomes "egg". The app's UI
/// is translated but food names stay English, so without this the meal search
/// would find nothing for a Cyrillic query.
///
/// Each word, or a known phrase such as "кисело млеко", is looked up in the
/// table and replaced. The last word may be unfinished, since the app searches
/// as you type: "пил" already means chicken. Cyrillic words with no entry are
/// dropped. Latin words and numbers are kept, so "протеин 80" stays useful.
///
/// Keys are lowercase, already normalized like
/// <c>FoodService.Normalize</c>. English values are what an English speaker
/// would type: singular, with the main word first ("chicken breast").
/// </summary>
public static partial class MacedonianFoodAliases
{
    private const int MinPrefixLength = 3;
    private const int MaxPhraseWords = 3;

    /// <summary>The English query for a normalized Cyrillic query, or null when
    /// <paramref name="normalizedQuery"/> has no Cyrillic or nothing in it is known.</summary>
    public static string? ToEnglishQuery(string normalizedQuery)
    {
        if (string.IsNullOrWhiteSpace(normalizedQuery) || !Cyrillic().IsMatch(normalizedQuery))
        {
            return null;
        }

        var tokens = normalizedQuery.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var output = new List<string>();
        var translatedAny = false;

        for (var i = 0; i < tokens.Length;)
        {
            var consumed = 0;
            for (var words = Math.Min(MaxPhraseWords, tokens.Length - i); words >= 1 && consumed == 0; words--)
            {
                var phrase = string.Join(' ', tokens, i, words);
                var isLastToken = i + words == tokens.Length;
                var english = Lookup(phrase, words, allowPrefix: isLastToken);
                if (english is not null)
                {
                    output.Add(english);
                    translatedAny = true;
                    consumed = words;
                }
            }

            if (consumed == 0)
            {
                if (!Cyrillic().IsMatch(tokens[i]))
                {
                    output.Add(tokens[i]);
                }

                consumed = 1;
            }

            i += consumed;
        }

        return translatedAny ? string.Join(' ', output) : null;
    }

    private static string? Lookup(string phrase, int words, bool allowPrefix)
    {
        if (Aliases.TryGetValue(phrase, out var exact))
        {
            return exact;
        }

        // Still typing the last word: the shortest key it starts is the closest guess.
        // Inside a phrase the finished words already narrow it down, so a single
        // letter is enough there.
        var lastWord = phrase[(phrase.LastIndexOf(' ') + 1)..];
        if (!allowPrefix || lastWord.Length < (words > 1 ? 1 : MinPrefixLength))
        {
            return null;
        }

        string? bestKey = null;
        foreach (var key in Aliases.Keys)
        {
            if (key.StartsWith(phrase, StringComparison.Ordinal)
                && WordCount(key) == words
                && (bestKey is null || key.Length < bestKey.Length))
            {
                bestKey = key;
            }
        }

        return bestKey is null ? null : Aliases[bestKey];
    }

    private static int WordCount(string value) => value.Count(c => c == ' ') + 1;

    [GeneratedRegex(@"\p{IsCyrillic}")]
    private static partial Regex Cyrillic();

    private static readonly IReadOnlyDictionary<string, string> Aliases = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        // Poultry, meat, fish
        ["пиле"] = "chicken", ["пилешко"] = "chicken", ["пилешки"] = "chicken", ["пилешка"] = "chicken",
        ["пилешки гради"] = "chicken breast", ["пилешко филе"] = "chicken breast", ["гради"] = "breast",
        ["батак"] = "chicken drumstick", ["батаци"] = "chicken drumstick", ["крилца"] = "chicken wing",
        ["мисирка"] = "turkey", ["мисиркино"] = "turkey", ["мисиркини"] = "turkey",
        ["говедско"] = "beef", ["говедски"] = "beef", ["говедина"] = "beef", ["јунешко"] = "beef", ["телешко"] = "veal",
        ["свинско"] = "pork", ["свински"] = "pork", ["свинска"] = "pork", ["јагнешко"] = "lamb", ["јагнешки"] = "lamb",
        ["мелено месо"] = "ground beef", ["мелено"] = "ground", ["месо"] = "meat", ["стек"] = "steak", ["шницла"] = "schnitzel",
        ["шунка"] = "ham", ["сланина"] = "bacon", ["колбас"] = "sausage", ["колбаси"] = "sausage", ["кобасица"] = "sausage",
        ["виршла"] = "frankfurter", ["виршли"] = "frankfurter", ["салама"] = "salami", ["пршута"] = "prosciutto", ["црн дроб"] = "liver",
        ["риба"] = "fish", ["туна"] = "tuna", ["лосос"] = "salmon", ["пастрмка"] = "trout", ["ослич"] = "hake",
        ["скуша"] = "mackerel", ["сардини"] = "sardine", ["сардина"] = "sardine", ["ракчиња"] = "shrimp", ["шкампи"] = "shrimp",
        ["лигњи"] = "squid", ["октопод"] = "octopus",

        // Eggs and dairy
        ["јајце"] = "egg", ["јајца"] = "egg", ["белка"] = "egg white", ["белки"] = "egg white", ["жолчка"] = "egg yolk",
        ["млеко"] = "milk", ["кравјо млеко"] = "milk", ["козјо млеко"] = "goat milk", ["чоколадно млеко"] = "chocolate milk",
        ["кисело млеко"] = "yogurt", ["јогурт"] = "yogurt", ["грчки јогурт"] = "greek yogurt", ["пробиотик"] = "kefir", ["кефир"] = "kefir",
        ["сирење"] = "cheese", ["бело сирење"] = "feta cheese", ["кашкавал"] = "cheese", ["урда"] = "ricotta",
        ["моцарела"] = "mozzarella", ["пармезан"] = "parmesan", ["чедар"] = "cheddar", ["крем сирење"] = "cream cheese",
        ["путер"] = "butter", ["маргарин"] = "margarine", ["павлака"] = "sour cream", ["кајмак"] = "cream", ["слатка павлака"] = "cream",
        ["скир"] = "skyr", ["цотиџ"] = "cottage cheese", ["цотиџ сирење"] = "cottage cheese",

        // Grains, bread, pasta
        ["леб"] = "bread", ["бел леб"] = "white bread", ["интегрален леб"] = "whole wheat bread", ["интегрален"] = "whole wheat",
        ["ржан леб"] = "rye bread", ["ржан"] = "rye", ["тост"] = "toast", ["кифла"] = "roll", ["лепче"] = "bun", ["тортиља"] = "tortilla",
        ["ориз"] = "rice", ["бел ориз"] = "white rice", ["кафеав ориз"] = "brown rice", ["интегрален ориз"] = "brown rice",
        ["овес"] = "oats", ["овесни"] = "oats", ["овесни снегулки"] = "oats", ["овесна каша"] = "oatmeal", ["снегулки"] = "cereal",
        ["мусли"] = "muesli", ["гранола"] = "granola", ["корнфлекс"] = "corn flakes",
        ["тестенина"] = "pasta", ["тестенини"] = "pasta", ["шпагети"] = "spaghetti", ["макарони"] = "macaroni", ["пенне"] = "penne",
        ["брашно"] = "flour", ["пченица"] = "wheat", ["пченка"] = "corn", ["булгур"] = "bulgur", ["киноа"] = "quinoa",
        ["хељда"] = "buckwheat", ["палента"] = "polenta", ["пуканки"] = "popcorn", ["бурек"] = "burek", ["пита"] = "pie",
        ["пица"] = "pizza", ["палачинка"] = "pancake", ["палачинки"] = "pancake", ["крекер"] = "cracker", ["крекери"] = "cracker",
        ["двопек"] = "rusk", ["оризови крекери"] = "rice cake",

        // Legumes, nuts, seeds
        ["грав"] = "beans", ["тавче гравче"] = "beans", ["гравче"] = "beans", ["леќа"] = "lentils", ["наут"] = "chickpeas",
        ["грашок"] = "peas", ["соја"] = "soy", ["тофу"] = "tofu",
        ["кикирики"] = "peanut", ["кикиритки"] = "peanut", ["путер од кикирики"] = "peanut butter", ["кикирики путер"] = "peanut butter",
        ["бадеми"] = "almond", ["бадем"] = "almond", ["ореви"] = "walnut", ["орев"] = "walnut", ["лешници"] = "hazelnut",
        ["лешник"] = "hazelnut", ["индиски ореви"] = "cashew", ["кашу"] = "cashew", ["семки"] = "seeds",
        ["сончогледови семки"] = "sunflower seeds", ["тиквени семки"] = "pumpkin seeds", ["чиа"] = "chia seeds", ["ленено семе"] = "flaxseed",
        ["сусам"] = "sesame", ["тахан"] = "tahini", ["урми"] = "dates",

        // Vegetables
        ["компир"] = "potato", ["компири"] = "potato", ["сладок компир"] = "sweet potato", ["помфрит"] = "french fries",
        ["домат"] = "tomato", ["домати"] = "tomato", ["краставица"] = "cucumber", ["краставици"] = "cucumber",
        ["пиперка"] = "pepper", ["пиперки"] = "pepper", ["црн пипер"] = "black pepper", ["кромид"] = "onion", ["лук"] = "garlic",
        ["морков"] = "carrot", ["моркови"] = "carrot", ["зелка"] = "cabbage", ["кисела зелка"] = "sauerkraut",
        ["зелена салата"] = "lettuce", ["марула"] = "lettuce", ["салата"] = "salad", ["спанаќ"] = "spinach", ["брокула"] = "broccoli",
        ["карфиол"] = "cauliflower", ["тиквичка"] = "zucchini", ["тиквички"] = "zucchini", ["тиква"] = "pumpkin",
        ["модар патлиџан"] = "eggplant", ["патлиџан"] = "eggplant", ["печурки"] = "mushroom", ["печурка"] = "mushroom",
        ["цвекло"] = "beet", ["целер"] = "celery", ["магдонос"] = "parsley", ["праз"] = "leek", ["аспарагус"] = "asparagus",
        ["бамја"] = "okra", ["маслинки"] = "olives", ["маслинка"] = "olive", ["авокадо"] = "avocado", ["ајвар"] = "ajvar",
        ["кечап"] = "ketchup", ["мајонез"] = "mayonnaise", ["сенф"] = "mustard",

        // Fruit
        ["јаболко"] = "apple", ["јаболка"] = "apple", ["банана"] = "banana", ["банани"] = "banana", ["портокал"] = "orange",
        ["портокали"] = "orange", ["мандарина"] = "mandarin", ["мандарини"] = "mandarin", ["лимон"] = "lemon", ["грејпфрут"] = "grapefruit",
        ["круша"] = "pear", ["круши"] = "pear", ["грозје"] = "grapes", ["јагоди"] = "strawberries", ["јагода"] = "strawberry",
        ["малини"] = "raspberries", ["боровинки"] = "blueberries", ["цреши"] = "cherries", ["вишни"] = "sour cherries",
        ["праска"] = "peach", ["праски"] = "peach", ["кајсија"] = "apricot", ["кајсии"] = "apricot", ["слива"] = "plum", ["сливи"] = "plum",
        ["лубеница"] = "watermelon", ["диња"] = "melon", ["ананас"] = "pineapple", ["киви"] = "kiwi", ["манго"] = "mango",
        ["смокви"] = "figs", ["смоква"] = "fig", ["калинка"] = "pomegranate", ["суво грозје"] = "raisins", ["овошје"] = "fruit",

        // Oils, sweets, drinks, misc
        ["масло"] = "oil", ["маслиново масло"] = "olive oil", ["сончогледово масло"] = "sunflower oil", ["зејтин"] = "oil",
        ["шеќер"] = "sugar", ["мед"] = "honey", ["џем"] = "jam", ["мармалад"] = "jam", ["чоколадо"] = "chocolate",
        ["чоколада"] = "chocolate", ["нутела"] = "nutella", ["бисквити"] = "cookies", ["колач"] = "cake", ["торта"] = "cake",
        ["сладолед"] = "ice cream", ["чипс"] = "chips", ["протеин"] = "protein", ["протеински прав"] = "whey protein",
        ["протеинска"] = "protein", ["протеински"] = "protein", ["протеинско"] = "protein", ["чоколадица"] = "bar",
        ["кафе"] = "coffee", ["чај"] = "tea", ["сок"] = "juice", ["портокалов сок"] = "orange juice", ["вода"] = "water",
        ["пиво"] = "beer", ["вино"] = "wine", ["кока кола"] = "coca cola", ["супа"] = "soup", ["чорба"] = "soup",
        ["сендвич"] = "sandwich", ["хамбургер"] = "hamburger", ["бургер"] = "burger", ["гирос"] = "gyro", ["ќебапи"] = "kebab",
        ["ќебап"] = "kebab", ["плескавица"] = "burger", ["сарма"] = "cabbage rolls", ["мусака"] = "moussaka",
        ["варено"] = "boiled", ["варени"] = "boiled", ["варен"] = "boiled", ["печено"] = "roasted", ["печени"] = "roasted",
        ["пржено"] = "fried", ["пржени"] = "fried", ["скара"] = "grilled", ["суров"] = "raw", ["сурово"] = "raw", ["сурови"] = "raw",
        ["посно"] = "lean",
    };
}
