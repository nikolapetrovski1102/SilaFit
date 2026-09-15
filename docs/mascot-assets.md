# Silen mascot assets

Updated September 15, 2026 from the supplied `new_mascot_pose` set.

## Sources and outputs

- Supplied `ready_pose.png`, `lifting_pose.png`, and `resting_pose.png` replace the corresponding assets without changing their artwork.
- `celebrating.png` and `proud.png` were generated with the built-in image generation tool using the supplied ready/lifting artwork as references.
- All five poses are 1024 × 1024 transparent PNGs in `frontend/assets/mascot/` and `website/assets/img/mascot/`.
- The supplied `icon.png` is centered and packaged into the branding assets in both projects. The launcher image uses the existing light background; splash and adaptive foregrounds preserve transparency. Android adaptive artwork has extra safe-area padding.
- Existing Android, iOS (`SilaFit`), macOS, web, and Windows icon/splash raster resources were refreshed at their existing dimensions. No pose names or consuming code changed.

## Generation prompts

### Celebrating

Use case: stylized-concept. Create a single production PNG mascot asset for SilenFit, celebrating workout completion. Reference image 1 ready_pose is the definitive character and rendering style; reference image 2 lifting_pose supplies matching gold barbell detail. Preserve exactly the same lime yellow-green round bald head, dark simple eyes and expressive eyebrows, muscular humanoid anatomy with defined pecs, abs and limbs, glossy painted highlights, olive-green shaded contours, tan-gold wristbands, thin white sticker perimeter. Full body, both arms raised in a victorious V with clenched fists and joyful smiling face. A gold-plated barbell rests in foreground at feet; sparse gold/lime confetti and small celebratory sparkles around shoulders. Match reference proportions and illustration detail, no clothing like the ready reference, no text. Centered square 1024x1024 composition, entire character and props within canvas, oval dark green ground shadow with lime center underneath, approximately same character size and baseline as references. Genuine transparent background, no black or white fill and no checkerboard. This must look like another pose from the exact same illustrated mascot set, not a redesigned character.

The first output contained a rendered checkerboard. A follow-up background-extraction edit removed it and requested actual RGBA transparency while preserving the artwork.

### Proud

Use case: stylized-concept. Create a single production PNG mascot asset for SilenFit, proud after a personal record or streak milestone. Reference image ready_pose is the definitive character and rendering style. Preserve exactly the same lime yellow-green round bald head, dark simple eyes and expressive eyebrows, muscular humanoid anatomy with defined pecs, abs and limbs, glossy painted highlights, olive-green shaded contours, tan-gold wristbands, thin white sticker perimeter. Full body facing forward in a double-biceps flex pose, elbows out and fists near head height, shoulders proud, confident friendly closed smile. A few small gold/lime star sparkles around shoulders. Match reference proportions and illustration detail, no clothing like ready reference, no text, no weights or extra props. Centered square 1024x1024 composition, entire character within canvas, oval dark green ground shadow with lime center underneath, approximately same character size and baseline as reference. Genuine transparent background, no black or white fill and no checkerboard. This must look like another pose from the exact same illustrated mascot set, not a redesigned character.
