import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tetrofall/services/connectivity_service.dart';

/// Covers the part of connectivity that the ads recovery depends on: the
/// answer is only ever "yes" once a probe has said so, and a "no" keeps
/// checking back on its own rather than waiting for an event that may not
/// come.
void main() {
  late StreamController<List<ConnectivityResult>> changes;
  late int probes;
  late bool reachable;

  setUp(() {
    changes = StreamController<List<ConnectivityResult>>.broadcast();
    probes = 0;
    reachable = true;
  });

  ConnectivityService build() => ConnectivityService(
    changes: changes.stream,
    probe: () async {
      probes++;
      return reachable;
    },
  );

  test('starts offline and turns online only once a probe agrees', () {
    fakeAsync((async) {
      final service = build();
      expect(service.isOnline.value, isFalse);

      async.flushMicrotasks();

      expect(probes, 1);
      expect(service.isOnline.value, isTrue);
      service.dispose();
    });
  });

  test('a link with no route through it stays offline', () {
    fakeAsync((async) {
      reachable = false;
      final service = build();
      async.flushMicrotasks();

      // The radio says wifi. The probe says otherwise, and the probe wins —
      // this is the captive-portal case, and requesting an ad here would fail.
      changes.add([ConnectivityResult.wifi]);
      async.flushMicrotasks();

      expect(service.isOnline.value, isFalse);
      service.dispose();
    });
  });

  test('no link is offline without spending a probe on it', () {
    fakeAsync((async) {
      final service = build();
      async.flushMicrotasks();
      expect(service.isOnline.value, isTrue);

      final before = probes;
      changes.add([ConnectivityResult.none]);
      async.flushMicrotasks();

      expect(service.isOnline.value, isFalse);
      expect(probes, before, reason: 'no route to probe');
      service.dispose();
    });
  });

  test('keeps re-probing while offline, and stops once online', () {
    fakeAsync((async) {
      reachable = false;
      final service = build();
      async.flushMicrotasks();
      expect(probes, 1);

      // Backs off rather than hammering: 5s, then 10s, then 20s.
      async.elapse(const Duration(seconds: 5));
      expect(probes, 2);
      async.elapse(const Duration(seconds: 5));
      expect(probes, 2, reason: 'second wait is longer than the first');
      async.elapse(const Duration(seconds: 5));
      expect(probes, 3);

      // The network comes back with no event to announce it — which is the
      // whole reason this timer exists.
      reachable = true;
      async.elapse(const Duration(seconds: 20));
      expect(service.isOnline.value, isTrue);

      final settled = probes;
      async.elapse(const Duration(minutes: 5));
      expect(probes, settled, reason: 'nothing polls while online');
      service.dispose();
    });
  });

  test('refresh() probes immediately instead of waiting out the backoff', () {
    fakeAsync((async) {
      reachable = false;
      final service = build();
      async.flushMicrotasks();
      expect(probes, 1);

      reachable = true;
      service.refresh();
      async.flushMicrotasks();

      expect(service.isOnline.value, isTrue);
      service.dispose();
    });
  });

  test('a link event resets the backoff so recovery is not delayed', () {
    fakeAsync((async) {
      reachable = false;
      final service = build();
      async.flushMicrotasks();
      // Walk the backoff up to its longer steps.
      async.elapse(const Duration(minutes: 2));
      final grown = probes;

      changes.add([ConnectivityResult.mobile]);
      async.flushMicrotasks();
      expect(probes, grown + 1, reason: 'a link event probes at once');

      // And the next wait is the first step again, not the grown one.
      async.elapse(const Duration(seconds: 5));
      expect(probes, grown + 2);
      service.dispose();
    });
  });
}
