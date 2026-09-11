import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Uses catalogue metadata instead of scraping an image search engine.
class BookCoverSearch {
  static String normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();

  static String searchTitle(String value) {
    var title = value
        .replaceAll('_', ' ')
        .replaceFirst(RegExp(r'\.(m4b|mp3|m4a)$', caseSensitive: false), '')
        .replaceAll(
            RegExp(r'\((?:unabridged|audiobook)[^)]*\)', caseSensitive: false),
            '')
        .trim();
    final parts = title.split(RegExp(r'\s+[-–—]\s+'));
    if (parts.length > 1 &&
        RegExp(r'^(the|a|an|\d+)\s', caseSensitive: false).hasMatch(parts[1])) {
      title = parts.skip(1).join(' - ');
    }
    return title.split(':').first.trim();
  }

  static double relevance(
      String query, String candidate, String author, String candidateAuthor) {
    final q = normalize(searchTitle(query));
    final c = normalize(searchTitle(candidate));
    if (q.isEmpty || c.isEmpty) return 0;
    final words = q
        .split(' ')
        .where((w) => !{'the', 'a', 'an', 'of', 'and', 'to', 'in'}.contains(w))
        .toSet();
    final others = c.split(' ').toSet();
    if (words.isEmpty) return q == c ? 1 : 0;
    final coverage = words.intersection(others).length / words.length;
    final precision = words.intersection(others).length / others.length;
    if (coverage < 0.75 ||
        (q != c && precision < 0.75 && !c.startsWith('$q ')) ||
        (words.length == 1 && q != c && !c.startsWith('$q '))) {
      return 0;
    }
    final wantedAuthor =
        normalize(author).split(' ').where((s) => s.length > 2).toSet();
    final foundAuthor = normalize(candidateAuthor).split(' ').toSet();
    final authorMatch = wantedAuthor.isEmpty
        ? 0.0
        : wantedAuthor.intersection(foundAuthor).length / wantedAuthor.length;
    return (q == c ? 3 : coverage + precision) + authorMatch;
  }

  BookCoverSearch({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  final _cache = <String, List<String>>{};
  final _pending = <String, Future<List<String>>>{};
  static final instance = BookCoverSearch();

  Future<List<String>> search(String title, String author) async {
    title = searchTitle(title);
    author = author.trim();
    if (['unknown', 'unknown author', 'n/a'].contains(author.toLowerCase())) {
      author = '';
    }
    if (title.isEmpty) return [];
    final key = '${title.toLowerCase()}|${author.toLowerCase()}';
    if (_cache.containsKey(key)) return _cache[key]!;
    if (_pending.containsKey(key)) return _pending[key]!;
    final request = _search(title, author);
    _pending[key] = request;
    try {
      final results = await request;
      if (results.isNotEmpty) {
        if (_cache.length >= 30) _cache.remove(_cache.keys.first);
        _cache[key] = results;
      }
      return results;
    } finally {
      _pending.remove(key);
    }
  }

  Future<List<String>> _search(String title, String author) async {
    var succeeded = false;
    final candidates = <({String url, String title, String author})>[];
    Future<void> catalogue(String authorTerm) async {
      final uri = Uri.https('openlibrary.org', '/search.json', {
        'title': title,
        if (authorTerm.isNotEmpty) 'author': authorTerm,
        'fields': 'key,title,author_name,cover_i',
        'limit': '20',
      });
      final response = await _client.get(uri, headers: {
        'User-Agent': 'Aradia/3.0 (audiobook cover search)',
      }).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw HttpException('Cover catalogue unavailable');
      }
      final data = jsonDecode(response.body) as Map;
      succeeded = true;
      for (final book in (data['docs'] as List? ?? []).whereType<Map>()) {
        final id = book['cover_i'];
        if (id is num && id > 0) {
          candidates.add((
            url: 'https://covers.openlibrary.org/b/id/$id-L.jpg?default=false',
            title: book['title']?.toString() ?? '',
            author: (book['author_name'] as List? ?? []).join(' ')
          ));
        }
      }
    }

    Future<void> audiobookCovers({bool includeAuthor = true}) async {
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': includeAuthor ? '$title $author'.trim() : title,
        'entity': 'audiobook',
        'limit': '20',
      });
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw HttpException('Audiobook catalogue unavailable');
      }
      final data = jsonDecode(response.body) as Map;
      succeeded = true;
      for (final book in (data['results'] as List? ?? []).whereType<Map>()) {
        final url = book['artworkUrl100'];
        if (url is String) {
          candidates.add((
            url: url.replaceFirst('100x100', '600x600'),
            title:
                (book['collectionName'] ?? book['trackName'])?.toString() ?? '',
            author: book['artistName']?.toString() ?? ''
          ));
        }
      }
    }

    await Future.wait([
      catalogue(author).catchError((_) {}),
      audiobookCovers().catchError((_) {}),
    ]);
    double score(({String url, String title, String author}) c) =>
        relevance(title, c.title, author, c.author);
    if (!candidates.any((c) => score(c) > 0) && author.isNotEmpty) {
      await Future.wait([
        catalogue('').catchError((_) {}),
        audiobookCovers(includeAuthor: false).catchError((_) {})
      ]);
    }
    if (!succeeded) {
      throw const HttpException(
          'Could not reach the cover catalogues. Check your connection and retry.');
    }
    final ranked = candidates.where((c) => score(c) > 0).toList()
      ..sort((a, b) => score(b).compareTo(score(a)));
    return ranked.map((c) => c.url).toSet().take(30).toList();
  }

  Future<String> download(String url) async {
    final response =
        await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 ||
        response.bodyBytes.length > 10 * 1024 * 1024) {
      throw const HttpException(
          'Could not download this cover. Try another image.');
    }
    final codec = await ui.instantiateImageCodec(response.bodyBytes);
    codec
        .dispose(); // Reject HTML, error pages, or invalid image data before saving.
    final base = await getApplicationSupportDirectory();
    final directory =
        await Directory('${base.path}/covers').create(recursive: true);
    final file =
        File('${directory.path}/${DateTime.now().microsecondsSinceEpoch}.jpg');
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file.path;
  }
}
