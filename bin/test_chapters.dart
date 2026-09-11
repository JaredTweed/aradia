import 'dart:io';
import 'package:aradia/resources/services/local/chapter_parser.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stdout.writeln('Usage: dart run bin/test_chapters.dart <path-to-m4b>');
    exit(1);
  }

  final f = File(args.first);
  final cues = await ChapterParser.parseFile(f);
  stdout.writeln("chapters: ${cues.length}");
  for (var i = 0; i < cues.length; i++) {
    final c = cues[i];
    stdout.writeln("${i + 1}. ${c.startMs}ms  ${c.title}");
  }
}
