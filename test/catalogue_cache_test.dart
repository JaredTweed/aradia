import 'dart:async';
import 'package:aradia/resources/services/json_response_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('concurrent readers share a request and fresh data avoids HTTP',
      () async {
    var calls = 0;
    final response = Completer<http.Response>();
    final cache = JsonResponseCache(client: MockClient((_) {
      calls++;
      return response.future;
    }));
    final first = cache.get('https://example.test/books');
    final second = cache.get('https://example.test/books');
    response.complete(http.Response('{"books":[]}', 200));
    expect(await first, await second);
    expect(await cache.get('https://example.test/books'), '{"books":[]}');
    expect(calls, 1);
    cache.close();
  });
  test(
      'stale entries revalidate, refresh expiry, and survive a temporary outage',
      () async {
    var now = DateTime(2026);
    var calls = 0;
    final cache = JsonResponseCache(
        now: () => now,
        client: MockClient((request) async {
          calls++;
          if (calls == 1) {
            return http.Response('{"books":[]}', 200, headers: {'etag': 'one'});
          }
          expect(request.headers['If-None-Match'], 'one');
          if (calls == 2) return http.Response('', 304);
          throw http.ClientException('offline');
        }));
    await cache.get('https://example.test/books');
    now = now.add(const Duration(minutes: 6));
    await cache.get('https://example.test/books');
    await cache.get('https://example.test/books');
    expect(calls, 2);
    now = now.add(const Duration(minutes: 6));
    expect(await cache.get('https://example.test/books'), '{"books":[]}');
    now = now.add(const Duration(days: 2));
    await expectLater(cache.get('https://example.test/books'),
        throwsA(isA<http.ClientException>()));
    cache.close();
  });
}
