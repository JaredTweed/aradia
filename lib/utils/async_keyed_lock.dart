/// Serializes mutations of one resource without blocking unrelated resources.
class AsyncKeyedLock {
  final _pending = <String, Future<void>>{};

  Future<T> run<T>(String key, Future<T> Function() action) {
    final result =
        (_pending[key] ?? Future<void>.value()).then((_) => action());
    final tail =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _pending[key] = tail;
    return result.whenComplete(() {
      if (identical(_pending[key], tail)) _pending.remove(key);
    });
  }
}
