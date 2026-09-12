import 'dart:math' as math;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:aradia/resources/archive_api.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/history_of_audiobook.dart';

class RecommendationProfile {
  final genres = <String, double>{};
  final authors = <String, double>{};
  final seen = <String>{};
  final seenTitles = <String>{};
  static String normalize(String value) =>
      value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  static String bookIdentity(Audiobook book) =>
      '${normalize(book.title)}|${normalize(book.author ?? '')}';

  RecommendationProfile(List<HistoryOfAudiobookItem> history,
      List<Audiobook> favorites, List<String> selected,
      {DateTime? now}) {
    final today = now ?? DateTime.now();
    for (final genre in selected) {
      _addGenre(genre, 6);
    }
    for (final item in history) {
      final engaged = item.index > 0 || item.position >= 120000;
      final days = math.max(0, today.difference(item.lastModified).inDays);
      _addBook(
          item.audiobook, (engaged ? 3.0 : 0.3) * math.pow(0.5, days / 90));
    }
    for (final book in favorites) {
      _addBook(book, 5);
    }
  }

  void _addGenre(String value, double weight) {
    for (final part in value.split(RegExp('[;&]'))) {
      final genre = normalize(part);
      if (genre.isEmpty ||
          const {
            'librivox',
            'audiobooks',
            'audiobook',
            'audio',
            'public domain'
          }.contains(genre)) {
        continue;
      }
      genres.update(genre, (v) => v + weight, ifAbsent: () => weight);
    }
  }

  void _addBook(Audiobook book, double weight) {
    seen.add(book.id);
    seenTitles.add(bookIdentity(book));
    for (final genre in book.subject ?? []) {
      _addGenre(genre.toString(), weight);
    }
    final author = normalize(book.author ?? '');
    if (author.isNotEmpty &&
        !author.startsWith('unknown') &&
        author != 'various') {
      authors.update(author, (v) => v + weight, ifAbsent: () => weight);
    }
  }

  List<String> get topGenres =>
      genres.keys.toList()..sort((a, b) => genres[b]!.compareTo(genres[a]!));
  List<String> get topAuthors =>
      authors.keys.toList()..sort((a, b) => authors[b]!.compareTo(authors[a]!));

  List<Audiobook> rank(List<Audiobook> candidates, {int limit = 30}) {
    final unique = <String, Audiobook>{};
    for (final book in candidates) {
      if (!seen.contains(book.id) && !seenTitles.contains(bookIdentity(book))) {
        unique.putIfAbsent(bookIdentity(book), () => book);
      }
    }
    double score(Audiobook book) {
      final affinity = (book.subject ?? []).fold<double>(
          0, (sum, genre) => sum + (genres[normalize(genre.toString())] ?? 0));
      final reviews = math.max(0, book.reviews ?? 0);
      final rating = ((book.rating ?? 0).clamp(0, 5) * reviews + 3.5 * 10) /
          (reviews + 10);
      return math.log(1 + affinity) * 3 +
          math.log(1 + (authors[normalize(book.author ?? '')] ?? 0)) * 2 +
          rating * 0.5 +
          math.log(1 + math.max(0, book.downloads ?? 0)) * 0.12;
    }

    final remaining = unique.values.toList();
    final scores = {for (final book in remaining) book: score(book)};
    final normalizedAuthors = {
      for (final book in remaining) book: normalize(book.author ?? '')
    };
    final result = <Audiobook>[];
    final authorCounts = <String, int>{};
    while (remaining.isNotEmpty && result.length < limit) {
      double diversified(Audiobook b) =>
          scores[b]! - (authorCounts[normalizedAuthors[b]] ?? 0) * 2.5;
      var best = 0;
      var bestScore = diversified(remaining.first);
      for (var i = 1; i < remaining.length; i++) {
        final candidateScore = diversified(remaining[i]);
        if (candidateScore > bestScore ||
            (candidateScore == bestScore &&
                remaining[i].id.compareTo(remaining[best].id) < 0)) {
          best = i;
          bestScore = candidateScore;
        }
      }
      final next = remaining.removeAt(best);
      result.add(next);
      authorCounts.update(normalize(next.author ?? ''), (v) => v + 1,
          ifAbsent: () => 1);
    }
    return result;
  }
}

class RecommendationService {
  Future<List<Audiobook>> getRecommendations() async {
    await HistoryOfAudiobook().isHistoryEmpty();
    final prefs = await Hive.openBox('recommened_audiobooks_box');
    final favorites = await Hive.openBox('favourite_audiobooks_box');
    final profile = RecommendationProfile(
        HistoryOfAudiobook().getHistory(),
        favorites.values
            .whereType<Map>()
            .map((m) => Audiobook.fromMap(m))
            .toList(),
        List<String>.from(
            prefs.get('selectedGenres', defaultValue: <String>[])));
    final api = ArchiveApi();
    String quote(String s) => '"${s.replaceAll(RegExp(r'["\\]'), ' ')}"';
    final requests = [
      for (final genre in profile.topGenres.take(3))
        api.getAudiobooksByGenre(quote(genre), 1, 35, 'downloads'),
      for (final author in profile.topAuthors.take(1))
        api.searchAudiobook('creator:${quote(author)}', 1, 25),
      api.getMostViewedWeeklyAudiobook(1, 35),
    ];
    final candidates = <Audiobook>[];
    var succeeded = false;
    for (final response in await Future.wait(requests)) {
      response.fold((_) {}, (books) {
        succeeded = true;
        candidates.addAll(books);
      });
    }
    if (!succeeded) {
      throw Exception(
          'Recommendations could not load. Check your connection and retry.');
    }
    return profile.rank(candidates);
  }
}
