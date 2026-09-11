import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('archive metadata accepts list-valued fields and malformed dates', () {
    final book = Audiobook.fromJson({
      'identifier': 'book',
      'title': 'Book',
      'creator': ['First', 'Second'],
      'language': ['en', 'fr'],
      'description': ['One', 'Two'],
      'date': 'unknown',
      'downloads': '42',
      'avg_rating': 'invalid',
    });
    expect(book.author, 'First, Second');
    expect(book.downloads, 42);
    expect(book.date, isNull);
    expect(book.rating, isNull);
  });
  test('copyWith serializes an explicitly changed date', () {
    final date = DateTime.utc(2026, 9, 11);
    expect(Audiobook.empty().copyWith(date: date).date, date);
  });
  test(
      'audio URLs escape reserved filename characters and absent cover stays absent',
      () {
    final file = AudiobookFile.fromJson({
      'identifier': 'book',
      'name': 'Chapter #1?.mp3',
      'length': '01:02:03.5',
      'track': '2/10',
    });
    expect(Uri.parse(file.url!).pathSegments.last, 'Chapter #1?.mp3');
    expect(Uri.parse(file.url!).hasQuery, false);
    expect(Uri.parse(file.url!).hasFragment, false);
    expect(file.highQCoverImage, isNull);
    expect(file.length, 3723.5);
    expect(file.track, 2);
  });
  test('saved audio lengths tolerate integer JSON values', () {
    expect(AudiobookFile.fromMap({'length': 12}).length, 12.0);
  });
}
