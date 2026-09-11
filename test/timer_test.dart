import 'package:aradia/utils/optimized_timer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sleep timer accounts for time spent suspended', (tester) async {
    var now = DateTime(2026);
    var expirations = 0;
    final timer = OptimizedTimer(now: () => now);
    timer.start(
        duration: const Duration(minutes: 15), onExpired: () => expirations++);
    now = now.add(const Duration(minutes: 16));
    await tester.pump(const Duration(seconds: 1));
    expect(expirations, 1);
    expect(timer.isActive.value, false);
    await tester.pump(const Duration(seconds: 2));
    expect(expirations, 1);
    timer.dispose();
  });
  testWidgets('replacing and canceling a timer prevents stale expiration',
      (tester) async {
    var now = DateTime(2026);
    var expirations = 0;
    final timer = OptimizedTimer(now: () => now);
    timer.start(
        duration: const Duration(seconds: 1), onExpired: () => expirations++);
    timer.start(
        duration: const Duration(minutes: 1), onExpired: () => expirations++);
    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(expirations, 0);
    timer.cancel();
    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(expirations, 0);
    timer.dispose();
  });
}
