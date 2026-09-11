import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/history_of_audiobook.dart';
import 'package:aradia/resources/services/recommendation_service.dart';
import 'package:flutter_test/flutter_test.dart';

Audiobook book(String id, String author, String genre) => Audiobook.fromMap({
      'id': id,
      'title': id,
      'author': author,
      'subject': [genre]
    });
void main() {
  test(
      'preferences rank relevant books, exclude known books and diversify authors',
      () {
    final favorite = book('saved', 'Author A', 'mystery');
    final profile = RecommendationProfile([], [favorite], ['mystery']);
    final result = profile.rank([
      favorite,
      book('a1', 'Author A', 'mystery'),
      book('a2', 'Author A', 'mystery'),
      book('b1', 'Author B', 'mystery'),
      book('c1', 'Author C', 'science')
    ]);
    expect(result.map((b) => b.id), isNot(contains('saved')));
    expect(result.first.id, 'a1');
    expect(result.take(3).map((b) => b.author).toSet(), hasLength(2));
    expect(result.last.id, 'c1');
  });
  test(
      'recent engaged listening weighs more than old activity or accidental taps',
      () {
    final now = DateTime(2026, 9, 1);
    HistoryOfAudiobookItem item(
            String id, String genre, int days, int position) =>
        HistoryOfAudiobookItem(
            audiobook: book(id, id, genre),
            audiobookFiles: [],
            index: 0,
            position: position,
            lastModified: now.subtract(Duration(days: days)));
    final profile = RecommendationProfile([
      item('new', 'mystery', 0, 180000),
      item('old', 'horror', 180, 180000),
      item('tap', 'science', 0, 0)
    ], [], [], now: now);
    expect(profile.topGenres, ['mystery', 'horror', 'science']);
  });
  test('cold start and duplicate editions produce a stable useful list', () {
    final first = book('one', 'Author', 'mystery');
    final duplicate = first.copyWith(id: 'two');
    expect(RecommendationProfile([], [], []).rank([first, duplicate]),
        hasLength(1));
  });
}
