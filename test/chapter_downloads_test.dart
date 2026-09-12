import 'dart:io';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/resources/models/history_of_audiobook.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/services/download/chapter_downloads.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('concurrent manifest writes preserve every completed chapter', () async {
    final directory =
        await Directory.systemTemp.createTemp('aradia_concurrent');
    try {
      final entries = List.generate(
          8,
          (i) => ChapterDownloads.entry(
              AudiobookFile.fromMap(
                  {'title': 'Chapter $i', 'url': 'https://example.test/$i'}),
              i));
      for (final entry in entries) {
        await File('${directory.path}/${entry['filename']}')
            .writeAsString('audio');
      }
      await Future.wait(
          entries.map((entry) => ChapterDownloads.record(directory, entry)));
      expect(await ChapterDownloads.completed(directory), hasLength(8));
      await Future.wait(entries.take(4).map((entry) =>
          ChapterDownloads.delete(directory, entry['url'] as String)));
      expect(
          (await ChapterDownloads.completed(directory)).map((e) => e['order']),
          [4, 5, 6, 7]);
    } finally {
      await directory.delete(recursive: true);
    }
  });
  test('full catalogue remains visible with none, some or all downloaded',
      () async {
    final directory = await Directory.systemTemp.createTemp('aradia_catalogue');
    final catalogue = List.generate(
        3,
        (i) => AudiobookFile.fromMap({
              'title': 'Chapter $i',
              'url': 'https://example.test/$i.mp3',
              'length': 123.0,
            }));
    try {
      var playable =
          await ChapterDownloads.withDownloadedFiles(directory, catalogue);
      expect(playable.map((f) => f.url), catalogue.map((f) => f.url));
      for (final i in [1, 0, 2]) {
        final entry = ChapterDownloads.entry(catalogue[i], i);
        await File('${directory.path}/${entry['filename']}')
            .writeAsString('audio');
        await ChapterDownloads.record(directory, entry);
        playable =
            await ChapterDownloads.withDownloadedFiles(directory, catalogue);
        expect(playable, hasLength(3));
        expect(playable.map((f) => f.title), catalogue.map((f) => f.title));
        expect(playable[i].url, '${directory.path}/${entry['filename']}');
        expect(playable[i].duration, const Duration(seconds: 123));
        if (i == 1) {
          expect(playable[0].url, catalogue[0].url);
          expect(playable[2].url, catalogue[2].url);
        }
      }
      await ChapterDownloads.delete(directory, catalogue[1].url!);
      playable =
          await ChapterDownloads.withDownloadedFiles(directory, catalogue);
      expect(playable, hasLength(3));
      expect(playable[1].url, catalogue[1].url);
      expect(playable[0].url, isNot(catalogue[0].url));
    } finally {
      await directory.delete(recursive: true);
    }
  });
  test('resume survives switching between streaming and downloaded audio', () {
    final history = HistoryOfAudiobookItem(
        audiobook: Audiobook.empty(),
        audiobookFiles: [
          AudiobookFile.fromMap(
              {'title': 'Chapter two', 'url': '/chapter2.mp3'})
        ],
        index: 0,
        position: 42000,
        lastModified: DateTime.now());
    expect(
        history.indexIn([
          AudiobookFile.fromMap(
              {'title': 'Chapter one', 'url': 'https://example.test/1.mp3'}),
          AudiobookFile.fromMap(
              {'title': 'Chapter two', 'url': 'https://example.test/2.mp3'}),
        ]),
        1);
  });
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
