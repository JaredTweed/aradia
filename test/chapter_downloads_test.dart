import 'dart:io';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/resources/models/history_of_audiobook.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/services/download/chapter_downloads.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'adding chapters preserves catalogue order, completed files and durations',
      () async {
    final directory = await Directory.systemTemp.createTemp('aradia_chapters');
    try {
      Map<String, dynamic> entry(int i) => ChapterDownloads.entry(
          AudiobookFile.fromMap({
            'title': 'Chapter / $i',
            'url': 'https://example.test/$i.mp3',
            'length': 123.0
          }),
          i);
      final later = entry(8);
      final earlier = entry(1);
      for (final e in [later, earlier]) {
        await File('${directory.path}/${e['filename']}').writeAsString('audio');
        await ChapterDownloads.record(directory, e);
      }
      await ChapterDownloads.record(directory, later);
      final saved = await ChapterDownloads.completed(directory);
      expect(saved.map((e) => e['order']), [1, 8]);
      expect(saved.first['length'], 123.0);
      await ChapterDownloads.delete(directory, earlier['url'] as String);
      expect(await ChapterDownloads.completed(directory), hasLength(1));
      expect(await File('${directory.path}/${later['filename']}').exists(),
          isTrue);
      await ChapterDownloads.delete(directory, later['url'] as String);
      expect(await ChapterDownloads.completed(directory), isEmpty);
      await File('${directory.path}/${earlier['filename']}')
          .writeAsString('audio');
      await ChapterDownloads.record(directory, earlier);
      expect(await ChapterDownloads.completed(directory), hasLength(1));
    } finally {
      await directory.delete(recursive: true);
    }
  });
  test('resuming survives adding earlier chapters to an offline queue', () {
    final chapter = AudiobookFile.fromMap({'url': '/chapter9.mp3'});
    final history = HistoryOfAudiobookItem(
        audiobook: Audiobook.empty(),
        audiobookFiles: [chapter],
        index: 0,
        position: 42000,
        lastModified: DateTime.now());
    expect(
        history.indexIn([
          AudiobookFile.fromMap({'url': '/chapter2.mp3'}),
          chapter
        ]),
        1);
    expect(history.indexIn([]), -1);
  });
}
