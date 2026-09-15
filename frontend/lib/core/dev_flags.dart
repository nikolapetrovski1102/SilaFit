/// TEMPORARY development switch.
///
/// When true, developer-only tooling that is normally compiled out of release
/// builds is also enabled there: the Settings "Developer" section (replay
/// onboarding, simulate the monthly overview) and the monthly-overview preview
/// path that skips real profile/today reads. Set back to false to hide it again
/// before shipping a real build.
///
/// This is intentionally the single toggle - both call sites read it, so
/// reverting is a one-line change.
const bool kDevToolsInRelease = true;
