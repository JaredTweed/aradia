import 'dart:async';
import 'dart:io';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/resources/services/book_chapters_repository.dart';
import 'package:aradia/screens/audiobook_details/bloc/audiobook_details_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class DelayedChapters extends BookChaptersRepository {
  final pending = <String, Completer<BookChapters>>{};
  final started = <String, Completer<void>>{};
  @override
  Future<BookChapters> load(String id,
      {required bool isLocal,
      required bool isDownload,
      List<AudiobookFile>? fallback}) {
    final result = pending.putIfAbsent(id, () => Completer<BookChapters>());
    started.putIfAbsent(id, () => Completer<void>()).complete();
    return result.future;
  }

  Future<void> waitFor(String id) =>
      started.putIfAbsent(id, () => Completer<void>()).future;
}

void main() {
  test('a slow old details request cannot overwrite the latest book', () async {
    final directory = await Directory.systemTemp.createTemp('aradia_details');
    Hive.init(directory.path);
    await Hive.openBox('favourite_audiobooks_box');
    final repository = DelayedChapters();
    final bloc = AudiobookDetailsBloc(repository: repository);
    try {
      bloc.add(FetchAudiobookDetails('old', false, false));
      await repository.waitFor('old');
      bloc.add(FetchAudiobookDetails('new', false, false));
      await repository.waitFor('new');
      final loaded =
          bloc.stream.firstWhere((state) => state is AudiobookDetailsLoaded);
      repository.pending['new']!.complete(BookChapters([
        AudiobookFile.fromMap({'title': 'New'})
      ]));
      await loaded;
      repository.pending['old']!.completeError(StateError('stale failure'));
      await bloc.close();
      expect((bloc.state as AudiobookDetailsLoaded).audiobookFiles.single.title,
          'New');
    } finally {
      if (!bloc.isClosed) await bloc.close();
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });
}
