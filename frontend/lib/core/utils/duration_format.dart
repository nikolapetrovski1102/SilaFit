/// Formats a duration given in minutes as an "Xh Ym" label, e.g. 90 -> "1h 30m",
/// 60 -> "1h", 45 -> "45m".
String formatMinutesLabel(int minutes) {
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (hours == 0) return '${remainder}m';
  if (remainder == 0) return '${hours}h';
  return '${hours}h ${remainder}m';
}
