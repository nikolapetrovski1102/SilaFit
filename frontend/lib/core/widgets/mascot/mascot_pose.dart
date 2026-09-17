/// The app's mascot is named Silen. Used as the `semanticLabel` on every
/// mascot [Image.asset] so screen readers announce something meaningful
/// instead of skipping a purely decorative-looking image.
const mascotName = 'Silen';

/// The 4 mascot poses staged at `assets/mascot/*.png`, and the moments each
/// one is used for across the app:
/// - [celebrating] - workout complete.
/// - [proud] - a new PR or streak milestone.
/// - [resting] - Home's rest-day hero card state.
/// - [lifting] - an in-progress-workout flourish accent.
enum MascotPose { celebrating, lifting, proud, resting }

extension MascotPoseAsset on MascotPose {
  String get assetPath => 'assets/mascot/$name.png';
}
