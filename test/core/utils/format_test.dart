import 'package:flutter_test/flutter_test.dart';
import 'package:railnova/core/utils/format.dart';

void main() {
  group('formatDelay', () {
    test('shows plain minutes under 60', () {
      expect(formatDelay(0), '0 min');
      expect(formatDelay(1), '1 min');
      expect(formatDelay(45), '45 min');
      expect(formatDelay(59), '59 min');
    });

    test('switches to hours+minutes at exactly 60', () {
      // This is the boundary the original bug crossed: a train delayed by
      // 168 minutes was shown as "168 min" instead of "2h 48m".
      expect(formatDelay(60), '1h');
      expect(formatDelay(61), '1h 1m');
    });

    test('formats multi-hour delays', () {
      expect(formatDelay(120), '2h');
      expect(formatDelay(168), '2h 48m');
      expect(formatDelay(125), '2h 5m');
    });

    test('drops the minutes part when it is exactly zero', () {
      expect(formatDelay(180), '3h');
      expect(formatDelay(600), '10h');
    });

    test('handles large delays', () {
      expect(formatDelay(1440), '24h'); // a full day late
      expect(formatDelay(1500), '25h');
    });
  });
}
