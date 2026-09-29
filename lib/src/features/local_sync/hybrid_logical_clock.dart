class HybridLogicalTimestamp implements Comparable<HybridLogicalTimestamp> {
  const HybridLogicalTimestamp({
    required this.wallTimeMillis,
    required this.counter,
    required this.nodeId,
  });

  final int wallTimeMillis;
  final int counter;
  final String nodeId;

  factory HybridLogicalTimestamp.parse(String value) {
    final parts = value.split(':');
    if (parts.length < 3) {
      throw FormatException('Invalid hybrid logical timestamp.', value);
    }
    return HybridLogicalTimestamp(
      wallTimeMillis: int.parse(parts[0]),
      counter: int.parse(parts[1]),
      nodeId: parts.sublist(2).join(':'),
    );
  }

  @override
  int compareTo(HybridLogicalTimestamp other) {
    final wallComparison = wallTimeMillis.compareTo(other.wallTimeMillis);
    if (wallComparison != 0) {
      return wallComparison;
    }
    final counterComparison = counter.compareTo(other.counter);
    if (counterComparison != 0) {
      return counterComparison;
    }
    return nodeId.compareTo(other.nodeId);
  }

  @override
  String toString() => '$wallTimeMillis:$counter:$nodeId';

  @override
  bool operator ==(Object other) {
    return other is HybridLogicalTimestamp &&
        wallTimeMillis == other.wallTimeMillis &&
        counter == other.counter &&
        nodeId == other.nodeId;
  }

  @override
  int get hashCode => Object.hash(wallTimeMillis, counter, nodeId);
}

class HybridLogicalClock {
  HybridLogicalClock({
    required this.nodeId,
    DateTime Function()? now,
    HybridLogicalTimestamp? initial,
  }) : _now = now ?? DateTime.now,
       _last = initial;

  final String nodeId;
  final DateTime Function() _now;
  HybridLogicalTimestamp? _last;

  HybridLogicalTimestamp? get last => _last;

  HybridLogicalTimestamp tick() {
    final physicalMillis = _now().toUtc().millisecondsSinceEpoch;
    final previous = _last;
    final next =
        previous == null || physicalMillis > previous.wallTimeMillis
            ? HybridLogicalTimestamp(
              wallTimeMillis: physicalMillis,
              counter: 0,
              nodeId: nodeId,
            )
            : HybridLogicalTimestamp(
              wallTimeMillis: previous.wallTimeMillis,
              counter: previous.counter + 1,
              nodeId: nodeId,
            );
    _last = next;
    return next;
  }

  HybridLogicalTimestamp observe(HybridLogicalTimestamp remote) {
    final physicalMillis = _now().toUtc().millisecondsSinceEpoch;
    final previous = _last;
    final previousWall = previous?.wallTimeMillis ?? 0;
    final maxWall = <int>[
      physicalMillis,
      previousWall,
      remote.wallTimeMillis,
    ].reduce((int left, int right) => left > right ? left : right);

    int counter;
    if (maxWall == previousWall && maxWall == remote.wallTimeMillis) {
      final previousCounter = previous?.counter ?? 0;
      counter =
          (previousCounter > remote.counter
              ? previousCounter
              : remote.counter) +
          1;
    } else if (maxWall == previousWall) {
      counter = (previous?.counter ?? 0) + 1;
    } else if (maxWall == remote.wallTimeMillis) {
      counter = remote.counter + 1;
    } else {
      counter = 0;
    }

    final next = HybridLogicalTimestamp(
      wallTimeMillis: maxWall,
      counter: counter,
      nodeId: nodeId,
    );
    _last = next;
    return next;
  }
}
