import 'dart:async';
import 'package:aradia/utils/async_keyed_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'same resource waits, other resources proceed, and errors do not poison the queue',
      () async {
    final lock = AsyncKeyedLock();
    final gate = Completer<void>();
    final events = <String>[];
    final first = lock.run('book', () async {
      await gate.future;
      events.add('first');
      throw StateError('failure');
    });
    final failure = expectLater(first, throwsStateError);
    final second = lock.run('book', () async => events.add('second'));
    await lock.run('other', () async => events.add('other'));
    expect(events, ['other']);
    gate.complete();
    await failure;
    await second;
    await lock.run('book', () async => events.add('third'));
    expect(events, ['other', 'first', 'second', 'third']);
  });
}
