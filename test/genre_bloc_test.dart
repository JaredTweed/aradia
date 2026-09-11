import 'dart:async';
import 'package:aradia/resources/archive_api.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/screens/genre_audiobooks/bloc/genre_audiobooks_bloc.dart';
import 'package:aradia/utils/app_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

class GenreApi extends ArchiveApi {
  final requests = <Completer<Either<String, List<Audiobook>>>>[];
  @override
  Future<Either<String, List<Audiobook>>> getAudiobooksByGenre(
      String genre, int page, int rows, String sortBy) {
    final result = Completer<Either<String, List<Audiobook>>>();
    requests.add(result);
    return result.future;
  }
}

Future<void> flushEvents() => Future<void>.delayed(Duration.zero);
void main() {
  test('language changes reload cached genres and ignore older requests',
      () async {
    final api = GenreApi();
    final bloc = GenreAudiobooksBloc(archiveApi: api);
    bloc.add(
        LoadInitialAudiobooksEvent(genre: 'adventure', listType: 'popular'));
    await flushEvents();
    AppEvents.languagesChanged.add(null);
    await flushEvents();
    expect(api.requests.length, 4);
    final fresh = Audiobook.fromMap({'id': 'fresh'});
    api.requests[1].complete(Right([fresh]));
    api.requests[2].complete(const Right([]));
    api.requests[3].complete(const Right([]));
    api.requests[0].complete(Right([
      Audiobook.fromMap({'id': 'stale'})
    ]));
    await flushEvents();
    expect(bloc.state.getAudiobooksForListType('popular').single.id, 'fresh');
    await bloc.close();
  });
  test('retry clears an earlier genre error', () async {
    final api = GenreApi();
    final bloc = GenreAudiobooksBloc(archiveApi: api);
    bloc.add(
        LoadInitialAudiobooksEvent(genre: 'adventure', listType: 'popular'));
    await flushEvents();
    api.requests[0].complete(const Left('offline'));
    await flushEvents();
    bloc.add(LoadInitialAudiobooksEvent(
        genre: 'adventure', listType: 'popular', refresh: true));
    await flushEvents();
    api.requests[1].complete(Right([
      Audiobook.fromMap({'id': 'book'})
    ]));
    await flushEvents();
    expect(bloc.state.getErrorForListType('popular'), isNull);
    expect(bloc.state.getAudiobooksForListType('popular'), hasLength(1));
    await bloc.close();
  });
}
