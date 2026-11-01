# Silen mascot redesign: concept prompts

Direction (chosen November 1, 2026): **bold 3D vinyl-toy style**, **lime (#B5E61D-ish) as an accent only**. Three concepts are being explored: a kettlebell creature, a Balkan lynx and an axolotl athlete.

Workflow:
1. Generate a **character sheet** for each concept (prompt A) and pick a winner.
2. Use the winning sheet as the **reference image** for every pose (prompt B), so all poses stay on-model.
3. Export each pose as a 1024 × 1024 transparent PNG. The poses replace `frontend/assets/mascot/{ready,lifting,resting,celebrating,proud}.png` and `website/assets/img/mascot/`, keeping the same file names so no code has to change.

Shared style block (append it to every prompt):

> Stylized 3D collectible vinyl toy render, soft subsurface plastic, gentle glossy highlights, rounded chunky proportions (large head, compact body), crisp readable silhouette at small sizes, soft studio lighting from top-left, subtle contact shadow only. Lime-green (#B5E61D) used only as an accent on gear (sweatband, straps, sneaker soles). Single character, centered, full body, square 1:1, plain solid light-grey background for easy cutout. No text, no logo, no extra characters.

---

## Concept 1: "Sila", the kettlebell creature

**A. Character sheet**
> Original mascot character design sheet: a living cast-iron kettlebell creature. Its round body is a matte graphite-charcoal kettlebell with faint hammered-iron texture, and the kettlebell handle arcs over its head like a crest. It has a big friendly expressive face set into the iron (large glossy eyes, thick determined eyebrows, wide grin), short sturdy arms with lime sweatbands, stubby legs with chunky white sneakers with lime soles. A small embossed weight number "16" on its belly is the only marking. Show front view, three-quarter view, back view, and four facial expressions (determined, joyful, smug-proud, sleepy). [shared style block]

**B. Poses** (attach the chosen sheet as reference)
- **ready**: standing tall, fists on hips, confident determined grin.
- **lifting**: mid goblet-squat holding a tiny lime dumbbell at chest, strained but happy face, little sweat drop.
- **resting**: curled up asleep on a folded lime gym towel, eyes closed, a small "z" bubble shape (no letters), handle drooping.
- **celebrating**: jumping off the ground, both arms up, mouth wide open laughing, lime and gold confetti around.
- **proud**: double-biceps flex, smug half-smile, one eyebrow raised, small gold sparkles; tiny cracks in the iron glowing lime as if it is bursting with strength.

### Kettlebell v2 (chosen direction, November 1, 2026)

The first sheet was on-model but generic: a grey ball with little contrast that reads like a bomb or bowling ball and disappears on dark UI. v2 adds signature details people will remember:
- a lime competition-style band painted around the equator (real competition kettlebells are color-coded by weight);
- lime irises, so the eyes become the brand's color hook;
- white chalk handprints on the handle and chalk-puff effects (authentic to the gym, and they animate well);
- a small chip on the handle as a battle scar;
- gunmetal iron with a cool blue sheen and a lime rim light, so it reads on dark backgrounds;
- a gap-tooth grin and chunky high-top sneakers for personality.

```
Original mascot character design sheet for a fitness app: "Sila", a living competition kettlebell with a big personality. Body: a squat, slightly pear-shaped gunmetal-iron kettlebell with a cool blue-steel sheen and subtle hammered texture. A bold glossy lime-green (#B5E61D) painted band wraps around its equator like a competition kettlebell, with a chunky embossed "16" on the band at the front. The thick handle arcs over the top like a crest, with a small chip knocked out of its top-right corner (a battle scar) and smudged white chalk handprints on it. Face set high on the body: oversized glossy eyes with lime-green irises and white catchlights, thick expressive brow ridges sculpted from the iron, a wide confident grin with one small gap between the front teeth. Short, chunky, rubbery arms with oversized fists and white chalk-dusted knuckles; stubby legs in chunky white high-top sneakers with lime soles and laces. Cheerful, cocky, lovable gym-buddy personality. Show front view, three-quarter view, back view, a top-down silhouette test in solid black, and five facial expressions: determined, laughing, smug-proud with one raised brow, sleepy with drooping eyelids, and shocked-amazed. Small white chalk-dust puffs around a few of the views. Stylized 3D collectible vinyl toy render, soft subsurface plastic, gentle glossy highlights, rounded chunky proportions, crisp readable silhouette at small sizes, soft studio key light from the top-left plus a lime rim light from behind, subtle contact shadows. Plain solid light-grey background. No other text, no logo, no extra characters.
```

## Concept 2: "Silen", the Balkan lynx

**A. Character sheet**
> Original mascot character design sheet: an athletic anthropomorphic Balkan lynx. Warm sandy-beige fur with soft dark spots, prominent black ear tufts, white muzzle and cheek ruff, short bobbed tail, amber eyes with a confident friendly expression. Sporty athletic build (fit, not bodybuilder-huge), wearing a lime headband, a charcoal sleeveless training top and charcoal shorts, with lime-accented sneakers. Show front view, three-quarter view, back view, and four facial expressions (focused, joyful, proud smirk, sleepy). [shared style block]

**B. Poses**
- **ready**: athletic stance, arms crossed, tail flicking, confident smile.
- **lifting**: deadlift lockout with a barbell that has charcoal plates and lime collars, focused face.
- **resting**: lying stretched out like a cat on a yoga mat, eyes closed, paws tucked, content.
- **celebrating**: leaping with one fist pumped up, mouth open in a roar-cheer, confetti.
- **proud**: standing on a small podium block, flexing one arm, chin up, ear tufts perked, sparkles.

## Concept 3: "Silen", the axolotl athlete

**A. Character sheet**
> Original mascot character design sheet: a chubby-strong anthropomorphic axolotl athlete. Soft peach-pink skin with a pearly sheen, six feathery external gill fronds framing the head in deeper coral-pink, small dark glossy eyes, permanent gentle smile, short powerful limbs with tiny four-fingered hands, long finned tail. Lime sweatbands on the wrists and a lime lifting belt. Show front view, three-quarter view, back view, and four facial expressions (determined, joyful, proud, sleepy). [shared style block]

**B. Poses**
- **ready**: bouncy stance, small fists raised like a boxer, gills perked up.
- **lifting**: overhead press with a small barbell, cheeks puffed with effort, tail braced on the floor.
- **resting**: floating asleep in a small round puddle or curled around a water bottle-shaped pillow, gills drooping softly.
- **celebrating**: spinning jump, arms out, gills flared, bubbles and confetti.
- **proud**: flexing a tiny but defined bicep, eyes closed in satisfaction, sparkles; a lime "regeneration" glow outline hinting at recovery.

---

## App icon (after a winner is picked)
> App icon of [winning character] head only, three-quarter view, centered, filling about 70% of the frame, on a solid deep charcoal (#16181D) rounded-square background with a soft lime rim light. [style: 3D vinyl toy, no text]

---

## Chosen direction: "Sila", the ember spirit (November 1, 2026)

The flame spirit was picked from a first sheet in the bold 2D sticker style. It has two variants, each matched to the palette in `frontend/lib/core/theme/app_colors.dart`:

| Role | Dark mode (default) | Light mode |
|---|---|---|
| App background | teal `#172D30` | cream `#F5EEDD` |
| Flame body | soft lime `#DEFB92` → core `#F7FFE0` | burgundy `#800020` → crimson `#B3263E` |
| Flame core / glow | near-white `#F7FFE0` | mustard gold `#F5C463` |
| Outline | deep olive `#1B2A14` | ink `#241B12` |
| Sparkles / extra accents | orange `#EEAF51` | mustard `#F5C463` |
| Sticker border | white | white `#FFFFFF` |

Fixes compared with the first sheet: hands always float at the same height and size, the angry face no longer has an off-palette orange mouth, the sleepy version keeps the same silhouette (dimmed and smaller, not desaturated olive), and all the inner shading follows one consistent pattern.

### Pose: "no screenshots" (capture shield)

Shown in screenshots and screen recordings instead of the app (iOS, `CaptureShieldView` in `frontend/ios/SilaFit/ScreenSecurityPlugin.swift`). The shield draws its own blurred, drifting background and the caption, so the art is **only the mascot, on a transparent background**. Attach the chosen flame sheet as the reference and generate both variants.

Export as 1024 × 1024 transparent PNGs:
- `frontend/assets/mascot/flame/dark/no_screenshots.png`
- `frontend/assets/mascot/flame/light/no_screenshots.png`

The shield picks them up automatically. Until they exist it shows `shocked.png`.

**Dark-mode variant**
```
Use the attached character sheet as the exact reference: "Sila", the ember-spirit flame mascot, bold 2D sticker style, same proportions, face shapes, floating hands and inner shading pattern. Pose: the flame holds up a small retro camera in one floating hand and covers its lens with the other hand's palm, in a friendly "no photos, please" gesture. Expression: playful and protective, one eye winking, small confident smile, not angry. Next to it floats a simple round "no camera" badge: a camera outline with a single diagonal strike-through, drawn in the same outline weight as the mascot. A few small orange (#EEAF51) sparkles around the camera. Colors: flame body soft lime (#DEFB92) blending to a near-white core (#F7FFE0), deep olive outline (#1B2A14), camera and badge in near-white (#F7FFE0) with olive outlines. Thick white sticker border around the whole group (mascot + camera + badge). Centered, filling about 75% of a square 1:1 frame, fully transparent background, no shadow outside the sticker border. No text, no letters, no logo, no extra characters.
```

**Light-mode variant**
```
Use the attached character sheet as the exact reference: "Sila", the ember-spirit flame mascot, bold 2D sticker style, same proportions, face shapes, floating hands and inner shading pattern. Pose: the flame holds up a small retro camera in one floating hand and covers its lens with the other hand's palm, in a friendly "no photos, please" gesture. Expression: playful and protective, one eye winking, small confident smile, not angry. Next to it floats a simple round "no camera" badge: a camera outline with a single diagonal strike-through, drawn in the same outline weight as the mascot. A few small mustard (#F5C463) sparkles around the camera. Colors: flame body burgundy (#800020) blending to crimson (#B3263E) with a mustard-gold (#F5C463) core glow, ink outline (#241B12), camera and badge in cream (#F5EEDD) with ink outlines. Thick white (#FFFFFF) sticker border around the whole group (mascot + camera + badge). Centered, filling about 75% of a square 1:1 frame, fully transparent background, no shadow outside the sticker border. No text, no letters, no logo, no extra characters.
```

App-icon-sized alternative (a single glyph, if the full pose reads too busy): *the flame's head and both floating hands only, hands crossed in an "X" in front of a small camera, same palette and sticker border as above.*
