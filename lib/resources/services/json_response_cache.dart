import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Bounded catalogue cache. Concurrent readers share the same request.
class JsonResponseCache {
  JsonResponseCache({http.Client? client, DateTime Function()? now})
      : _client = client ?? http.Client(),
        _now = now ?? DateTime.now;
  final http.Client _client;
  final DateTime Function() _now;
  final _entries = <String, _Entry>{};
  final _pending = <String, Future<String>>{};
  int _bytes = 0;
  static const freshFor = Duration(minutes: 5);
  static const staleFor = Duration(hours: 24);

  Future<String> get(String url) {
    final cached = _entries[url];
    if (cached != null && _now().difference(cached.time) < freshFor) {
      _entries.remove(url);
      _entries[url] = cached;
      return Future.value(cached.body);
    }
    return _pending.putIfAbsent(
        url,
        () => _load(url, cached).whenComplete(() {
              _pending.remove(url);
            }));
  }

  Future<String> _load(String url, _Entry? cached) async {
    try {
      final response = await _client.get(Uri.parse(url), headers: {
        if (cached?.etag != null) 'If-None-Match': cached!.etag!,
        if (cached?.modified != null) 'If-Modified-Since': cached!.modified!,
      }).timeout(const Duration(seconds: 20));
      final String body;
      if (response.statusCode == 304 && cached != null) {
        body = cached.body;
      } else if (response.statusCode == 200) {
        body = response.body;
        jsonDecode(body); // Never replace good data with a proxy error page.
      } else {
        throw http.ClientException(
            'Catalogue returned HTTP ${response.statusCode}');
      }
      final revalidated = response.statusCode == 304;
      final previous = _entries.remove(url);
      _bytes -= (previous?.body.length ?? 0) * 2;
      _entries[url] = _Entry(
          body,
          response.headers['etag'] ?? (revalidated ? cached?.etag : null),
          response.headers['last-modified'] ??
              (revalidated ? cached?.modified : null),
          _now());
      _bytes += body.length * 2;
      while (_entries.length > 60 || _bytes > 12 * 1024 * 1024) {
        _bytes -= _entries.remove(_entries.keys.first)!.body.length * 2;
      }
      return body;
    } catch (_) {
      if (cached != null && _now().difference(cached.time) < staleFor) {
        return cached.body;
      }
      rethrow;
    }
  }

  void close() => _client.close();
}

class _Entry {
  _Entry(this.body, this.etag, this.modified, this.time);
  final String body;
  final String? etag;
  final String? modified;
  final DateTime time;
}
