import 'dart:async';
import 'package:aradia/resources/archive_api.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/screens/search/bloc/search_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

class PendingSearch {
  PendingSearch(this.query, this.page);
  final String query;
  final int page;
  final response = Completer<Either<String, List<Audiobook>>>();
}

class FakeArchiveApi extends ArchiveApi {
  final requests = <PendingSearch>[];
  @override
  Future<Either<String, List<Audiobook>>> searchAudiobook(
      String query, int page, int rows) {
    final request = PendingSearch(query, page);
    requests.add(request);
    return request.response.future;
  }
}

Audiobook book(String id) => Audiobook.fromMap({'id': id, 'title': id});
Future<void> flushEvents() => Future<void>.delayed(Duration.zero);

void main() {
  test('a late response cannot overwrite a newer query', () async {
    final api = FakeArchiveApi();
    final bloc = SearchBloc(api: api);
    bloc.add(EventSearchIconClicked('old'));
    await flushEvents();
    bloc.add(EventSearchIconClicked('new'));
    await flushEvents();
    api.requests[1].response.complete(Right([book('new')]));
    await flushEvents();
    api.requests[0].response.complete(Right([book('old')]));
    await flushEvents();
    expect((bloc.state as SearchSuccess).audiobooks.single.id, 'new');
    await bloc.close();
  });
  test(
      'paging failures retry the same page; duplicate requests and books are ignored',
      () async {
    final api = FakeArchiveApi();
    final bloc = SearchBloc(api: api);
    bloc.add(EventSearchIconClicked('books'));
    await flushEvents();
    api.requests[0].response.complete(Right([book('one')]));
    await flushEvents();
    bloc.add(EventLoadMoreResults('books'));
    bloc.add(EventLoadMoreResults('books'));
    await flushEvents();
    expect(api.requests.length, 2);
    api.requests[1].response.complete(const Left('offline'));
    await flushEvents();
    expect(bloc.currentPage, 1);
    expect((bloc.state as SearchSuccess).error, 'offline');
    bloc.add(EventLoadMoreResults('books'));
    await flushEvents();
    expect(api.requests.last.page, 2);
    api.requests.last.response.complete(Right([book('one'), book('two')]));
    await flushEvents();
    expect((bloc.state as SearchSuccess).audiobooks.map((b) => b.id),
        ['one', 'two']);
    bloc.add(EventLoadMoreResults('books'));
    await flushEvents();
    api.requests.last.response.complete(const Right([]));
    await flushEvents();
    expect((bloc.state as SearchSuccess).hasMore, false);
    bloc.add(EventLoadMoreResults('books'));
    await flushEvents();
    expect(api.requests.length, 4);
    await bloc.close();
  });
  test('an old page cannot be appended to a new query', () async {
    final api = FakeArchiveApi();
    final bloc = SearchBloc(api: api);
    bloc.add(EventSearchIconClicked('old'));
    await flushEvents();
    api.requests[0].response.complete(Right([book('old')]));
    await flushEvents();
    bloc.add(EventLoadMoreResults('old'));
    await flushEvents();
    bloc.add(EventSearchIconClicked('new'));
    await flushEvents();
    api.requests[2].response.complete(Right([book('new')]));
    api.requests[1].response.complete(Right([book('old page 2')]));
    await flushEvents();
    expect((bloc.state as SearchSuccess).audiobooks.single.id, 'new');
    expect(bloc.currentPage, 1);
    await bloc.close();
  });
}
