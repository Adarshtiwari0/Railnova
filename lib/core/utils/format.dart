/// Formats a delay given in minutes as a human-readable string.
///
/// Below 60 minutes it's shown as a plain minute count ("45 min"); at or
/// above 60 it switches to hours + minutes ("2h 48m", or just "2h" when
/// the minute part is zero) instead of a raw, hard-to-parse number like
/// "168 min".
///
/// This used to be copy-pasted as a private `_formatDelay` in four
/// different widgets, which is how the raw-minutes bug slipped through in
/// two of them — they'd been added later and never wired up to any of the
/// existing copies. Having a single, tested implementation means that
/// class of bug can't happen again.
String formatDelay(int minutes) {
  if (minutes < 60) return "$minutes min";

  final hours = minutes ~/ 60;
  final remainder = minutes % 60;

  return remainder == 0 ? "${hours}h" : "${hours}h ${remainder}m";
}
