import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:aradia/resources/services/local/chapter_parser.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> u32(int value) =>
    (ByteData(4)..setUint32(0, value)).buffer.asUint8List();
List<int> u64(int value) =>
    (ByteData(8)..setUint64(0, value)).buffer.asUint8List();
List<int> atom(String type, List<int> data) =>
    [...u32(data.length + 8), ...ascii.encode(type), ...data];

void main() {
  test('QuickTime chapter text samples are read at their file offsets',
      () async {
    final chapters =
        await ChapterParser.parseFile(File('test/fixtures/chapter_track.m4b'));
    expect(chapters.map((c) => c.title), ['Introduction', 'Chapter One']);
    expect(chapters.map((c) => c.startMs), [0, 750]);
  });
  for (final version in [0, 1]) {
    test(
        'Nero chapter version $version uses correct offsets and timing after a large audio payload',
        () async {
      final directory = await Directory.systemTemp.createTemp('aradia_parser');
      try {
        final file = File('${directory.path}/book.m4b');
        final writer = await file.open(mode: FileMode.write);
        const payloadSize = 128 * 1024 * 1024;
        await writer.writeFrom([...u32(payloadSize), ...ascii.encode('mdat')]);
        await writer.setPosition(
            payloadSize); // Sparse audio payload should never be read into RAM.
        await writer.writeFrom(atom(
            'moov',
            atom(
                'udta',
                atom('chpl', [
                  version,
                  0,
                  0,
                  0,
                  if (version == 1) ...[0, 0, 0, 0],
                  2,
                  ...u64(0),
                  5,
                  ...ascii.encode('Intro'),
                  ...u64(90500 * 10000),
                  3,
                  ...ascii.encode('One'),
                ]))));
        await writer.close();
        final chapters = await ChapterParser.parseFile(file);
        expect(chapters.map((c) => c.title), ['Intro', 'One']);
        expect(chapters.map((c) => c.startMs), [0, 90500]);
      } finally {
        await directory.delete(recursive: true);
      }
    });
  }
  test('chapter durations show seconds, hours and unavailable values honestly',
      () {
    expect(AudiobookFile.fromMap({'durationMs': 32500}).durationLabel, '0:32');
    expect(
        AudiobookFile.fromMap({'durationMs': 90500, 'length': 0}).durationLabel,
        '1:30');
    expect(AudiobookFile.fromMap({'length': 3661}).durationLabel, '1:01:01');
    expect(AudiobookFile.fromMap({}).durationLabel, 'Duration unavailable');
  });
}
