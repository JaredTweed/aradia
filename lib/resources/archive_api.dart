import 'dart:convert';
import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:http/http.dart' as http;
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/utils/app_logger.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart' show listEquals;

// ─── Simple HTTP cache with ETag/Last-Modified ────────────────────────────────
class _CacheEntry {
  final String body;
  final String? etag;
  final String? lastModified;
  final DateTime storedAt;
  _CacheEntry({
    required this.body,
    this.etag,
    this.lastModified,
    required this.storedAt,
  });
}

/// Fields we want back from Archive.org
const _fields =
    "runtime,avg_rating,num_reviews,title,description,identifier,creator,date,downloads,subject,item_size,language";

/// Map UI language codes to Archive.org language tokens (2/3-letter codes + English name).
/// IMPORTANT: No Hindi (hi) because LibriVox has no Hindi catalog.
const Map<String, List<String>> _langAliases = {
  'en': ['en', 'eng', 'english'],
  'de': ['de', 'deu', 'ger', 'german'],
  'es': ['es', 'spa', 'spanish'],
  'fr': ['fr', 'fra', 'fre', 'french'],
  'nl': ['nl', 'nld', 'dut', 'dutch'],
  'mul': ['mul', 'multiple', 'multilingual'],
  'pt': ['pt', 'por', 'portuguese'],
  'it': ['it', 'ita', 'italian'],
  'ru': ['ru', 'rus', 'russian'],
  'el': ['el', 'ell', 'greek'],
  'grc': ['grc', 'ancient greek', 'ancient', 'greek'], // Ancient Greek
  'ja': ['ja', 'jpn', 'japanese'],
  'pl': ['pl', 'pol', 'polish'],
  'zh': ['zh', 'zho', 'chi', 'chinese'],
  'he': ['he', 'heb', 'hebrew'],
  'la': ['la', 'lat', 'latin'],
  'fi': ['fi', 'fin', 'finnish'],
  'sv': ['sv', 'swe', 'swedish'],
  'ca': ['ca', 'cat', 'catalan'],
  'da': ['da', 'dan', 'danish'],
  'eo': ['eo', 'epo', 'esperanto'],
};

// Memoize language clause across calls until prefs change
String? _memoLangClause;
List<String>? _memoSelected;

/// Build the language clause for Archive.org's `q=` param based on Hive prefs.
/// Returns an empty string if no languages are selected (no filter).
String _languageQueryClause() {
  final box = Hive.box('language_prefs_box');
  final selected = List<String>.from(
    box.get('selectedLanguages', defaultValue: <String>[]),
  );

  // Fast path if nothing changed
  if (_memoSelected != null &&
      _memoLangClause != null &&
      listEquals(selected, _memoSelected)) {
    return _memoLangClause!;
  }

  if (selected.isEmpty) {
    _memoSelected = selected;
    _memoLangClause = '';
    return '';
  }

  final parts = <String>[];
  for (final code in selected) {
    final aliases = _langAliases[code.toLowerCase()];
    if (aliases == null) continue; // ignore unsupported like 'hi'
    parts.add('language:(${aliases.join('+OR+')})');
  }
  if (parts.isEmpty) {
    _memoSelected = selected;
    _memoLangClause = '';
    return '';
  }
  final clause = '+AND+(${parts.join('+OR+')})';
  _memoSelected = selected;
  _memoLangClause = clause;
  return clause;
}

/// Build a full advancedsearch URL with a base collection, optional extra query,
/// sorting, paging, and injected language clause.
String _buildAdvancedSearchUrl({
  required String collection,
  String extraQuery = '',
  String sortBy = '',
  required int page,
  required int rows,
}) {
  final lang = _languageQueryClause();
  final sort = sortBy.isNotEmpty ? '&sort[]=$sortBy+desc' : '';

  // q=collection:(librivoxaudio)+AND+(language:...)+AND+(<extraQuery>)
  final qParts = <String>[
    'collection:($collection)',
  ];
  if (lang.isNotEmpty) {
    // `lang` already starts with "+AND+(...)"
    qParts[0] = '${qParts[0]}$lang';
  }
  if (extraQuery.isNotEmpty) {
    // Encode the extra query component to be safe with spaces/ORs, then wrap.
    final enc = Uri.encodeComponent(extraQuery);
    qParts.add('($enc)');
  }
  final q = 'q=${qParts.join('+AND+')}';

  return 'https://archive.org/advancedsearch.php?$q&fl=$_fields$sort&output=json&page=$page&rows=$rows';
}

/// Base English seeds per category (kept for backfill and for English itself).
const Map<String, List<String>> genresSubjectsJson = {
  "adventure": [
    "adventure",
    "exploration",
    "shipwreck",
    "voyage",
    "sea stories",
    "sailing",
    "battle",
    "treasure",
    "frontier",
    "Great War"
  ],
  "biography": [
    "biography",
    "autobiography",
    "memoirs",
    "memoir",
    "George Washington",
    "Life",
    "Jesus",
    "Nederlands"
  ],
  "children": [
    "children",
    "juvenile",
    "juvenile fiction",
    "juvenile literature",
    "kids",
    "fairy tales",
    "fairy tale",
    "nursery rhyme",
    "youth",
    "boys",
    "girls"
  ],
  "comedy": [
    "comedy",
    "humor",
    "satire",
    "farce",
    "mistaken identity",
  ],
  "crime": [
    "crime",
    "murder",
    "detective",
    "mystery",
    "Mystery",
    "thief",
    "suspense",
    "Christian fiction",
    "steal"
  ],
  "fantasy": [
    "fantasy",
    "fairy tales",
    "magic",
    "supernatural",
    "myth",
    "mythology",
    "myths",
    "legends",
    "ghost",
    "ghosts"
  ],
  "horror": [
    "horror",
    "terror",
    "ghost",
    "ghosts",
    "supernatural",
    "suspense",
  ],
  "humor": [
    "humor",
    "comedy",
    "satire",
    "farce",
    "mistaken identity",
  ],
  "love": [
    "romance",
    "love",
    "marriage",
    "love story",
    "relationships",
  ],
  "mystery": [
    "mystery",
    "Mystery",
    "crime",
    "murder",
    "detective",
    "suspense",
    "Christian fiction"
  ],
  "philosophy": [
    "philosophy",
    "ethics",
    "morality",
    "metaphysics",
    "logic",
  ],
  "poem": [
    "poetry",
    "poem",
    "short poetry",
    "long poetry",
    "poems",
    "nursery rhyme"
  ],
  "religion": [
    "religion",
    "god",
    "theology",
    "bible",
    "jesus",
    "christ",
    "quran",
    "buddha"
  ],
  "romance": [
    "romance",
    "love",
    "love story",
    "relationships",
    "marriage",
  ],
  "scifi": [
    "science fiction",
    "sci-fi",
    "space",
    "futurism",
    "technology",
  ],
  "war": [
    "war",
    "soldier",
    "world war",
  ]
};

class ArchiveApi {
  // Reuse one client to keep TCP alive & reduce handshake cost.
  static final http.Client _client = http.Client();

  // Very small in-memory cache (URL -> response + validators).
  static final Map<String, _CacheEntry> _cache = <String, _CacheEntry>{};
  static const Duration _maxStale = Duration(minutes: 15); // tune as you like
  static const int _maxEntries = 100; // tiny LRU-ish trim

  // Centralized GET with conditional requests.
  static Future<String> _getJson(String url) async {
    final headers = <String, String>{};
    final cached = _cache[url];

    if (cached != null &&
        DateTime.now().difference(cached.storedAt) < _maxStale) {
      if (cached.etag != null) headers['If-None-Match'] = cached.etag!;
      if (cached.lastModified != null) {
        headers['If-Modified-Since'] = cached.lastModified!;
      }
    }

    final resp = await _client
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 30));

    if (resp.statusCode == 304 && cached != null) {
      // Not modified — serve cached body
      return cached.body;
    }
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode} for $url');
    }

    final etag = resp.headers['etag'];
    final lastMod = resp.headers['last-modified'];

    // Store/refresh cache (simple trim to avoid unbounded growth)
    _cache[url] = _CacheEntry(
      body: resp.body,
      etag: etag,
      lastModified: lastMod,
      storedAt: DateTime.now(),
    );
    if (_cache.length > _maxEntries) {
      // Drop the stalest ~10% (super simple)
      final entries = _cache.entries.toList()
        ..sort((a, b) => a.value.storedAt.compareTo(b.value.storedAt));
      for (var i = 0; i < (_maxEntries / 10).ceil(); i++) {
        _cache.remove(entries[i].key);
      }
    }

    return resp.body;
  }

  // Optional: call this from app shutdown if you want.
  static void dispose() => _client.close();

  Future<Either<String, List<Audiobook>>> getLatestAudiobook(
    int page,
    int rows,
  ) async {
    final url = _buildAdvancedSearchUrl(
      collection: 'librivoxaudio',
      sortBy: 'addeddate',
      page: page,
      rows: rows,
    );
    return _fetchAudiobooks(url);
  }

  Future<Either<String, List<Audiobook>>> getMostViewedWeeklyAudiobook(
    int page,
    int rows,
  ) async {
    final url = _buildAdvancedSearchUrl(
      collection: 'librivoxaudio',
      sortBy: 'week',
      page: page,
      rows: rows,
    );
    return _fetchAudiobooks(url);
  }

  Future<Either<String, List<Audiobook>>> getMostDownloadedEverAudiobook(
    int page,
    int rows,
  ) async {
    final url = _buildAdvancedSearchUrl(
      collection: 'librivoxaudio',
      sortBy: 'downloads',
      page: page,
      rows: rows,
    );
    return _fetchAudiobooks(url);
  }

  Future<Either<String, List<Audiobook>>> getAudiobooksByGenre(
    String genre,
    int page,
    int rows,
    String sortBy,
  ) async {
    final genreQuery = genre
        .split(RegExp(r'\s+OR\s+',
            caseSensitive: false)) // split by any 'OR' variant
        .map((s) => s.trim().toLowerCase())
        .join(' OR '); // join back with uppercase OR

    final url = _buildAdvancedSearchUrl(
      collection: 'audio_bookspoetry',
      extraQuery: 'subject:($genreQuery)',
      sortBy: sortBy,
      page: page,
      rows: rows,
    );
    return _fetchAudiobooks(url);
  }

  Future<Either<String, List<AudiobookFile>>> getAudiobookFiles(
    String identifier,
  ) async {
    final url = "https://archive.org/metadata/$identifier/files?output=json";
    try {
      final body = await _getJson(url);
      final resJson = json.decode(body);

      final List result = resJson["result"] ?? const [];
      String? highQCoverImage = result.firstWhere(
        (item) =>
            item is Map &&
            item["source"] == "original" &&
            item["format"] == "JPEG",
        orElse: () => null,
      )?["name"];

      final files = <AudiobookFile>[];
      for (final item in result) {
        if (item is Map &&
            item["source"] == "original" &&
            (item["name"]?.toString().toLowerCase().endsWith('.mp3') ??
                false)) {
          item["identifier"] = identifier;
          item["highQCoverImage"] = highQCoverImage;
          files.add(AudiobookFile.fromJson(item));
        }
      }
      files.sort((a, b) {
        final trackOrder = (a.track ?? 0).compareTo(b.track ?? 0);
        return trackOrder != 0
            ? trackOrder
            : (a.name ?? '').compareTo(b.name ?? '');
      });
      return Right(files);
    } catch (e) {
      return Left(e.toString());
    }
  }

  Future<Either<String, List<Audiobook>>> searchAudiobook(
    String searchQuery,
    int page,
    int rows,
  ) async {
    // Encode the free-form query to avoid breaking the `q` param.
    final encoded = Uri.encodeComponent(searchQuery);
    final lang = _languageQueryClause(); // may be empty

    final q =
        '$encoded+AND+collection:(audio_bookspoetry)${lang.isNotEmpty ? lang : ''}';

    final url =
        "https://archive.org/advancedsearch.php?q=$q&fl=$_fields&sort[]=downloads+desc&output=json&page=$page&rows=$rows";
    AppLogger.debug('Search URL: $url', 'ArchiveApi');
    return _fetchAudiobooks(url);
  }

  Future<Either<String, List<Audiobook>>> _fetchAudiobooks(String url) async {
    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final docs =
            (decoded['response']['docs'] as List).cast<Map<String, dynamic>>();

        // De-dupe raw docs by Archive.org identifier before building models
        final byId = <String, Map<String, dynamic>>{};
        for (final d in docs) {
          final id = (d['identifier'] as String?)?.trim();
          if (id == null || id.isEmpty) continue;
          byId.putIfAbsent(id, () => d); // keep first
        }

        return Right(Audiobook.fromJsonArray(byId.values.toList()));
      } else {
        throw Exception('Failed to load audiobooks');
      }
    } catch (e) {
      return Left(e.toString());
    }
  }
}
