import 'package:flutter_test/flutter_test.dart';
import 'package:neuradix_pos/src/features/local_sync/hybrid_logical_clock.dart';

void main() {
  test('hybrid clock remains monotonic when physical time does not move', () {
    final now = DateTime.utc(2026, 9, 21, 12);
    final clock = HybridLogicalClock(nodeId: 'device-a', now: () => now);

    final first = clock.tick();
    final second = clock.tick();

    expect(first.counter, 0);
    expect(second.wallTimeMillis, first.wallTimeMillis);
    expect(second.counter, 1);
    expect(second.compareTo(first), greaterThan(0));
    expect(HybridLogicalTimestamp.parse(second.toString()), second);
  });

  test('observing a remote timestamp advances the local clock', () {
    final clock = HybridLogicalClock(
      nodeId: 'device-b',
      now: () => DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
    );
    final remote = const HybridLogicalTimestamp(
      wallTimeMillis: 2000,
      counter: 4,
      nodeId: 'device-a',
    );

    final observed = clock.observe(remote);

    expect(observed.wallTimeMillis, 2000);
    expect(observed.counter, 5);
    expect(observed.nodeId, 'device-b');
  });
}
