import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:aradia/resources/archive_api.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/utils/app_events.dart';
import 'package:meta/meta.dart';

part 'search_event.dart';
part 'search_state.dart';

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  int currentPage = 1;
  int _generation = 0;
  bool _loadingMore = false;
  bool _hasMore = true;
  final ArchiveApi _api;

  /// The last query that was explicitly submitted (button press / Enter).
  String? lastQuery;

  StreamSubscription<void>? _langSub;

  SearchBloc({ArchiveApi? api})
      : _api = api ?? ArchiveApi(),
        super(SearchInitial()) {
    on<EventSearchIconClicked>(_onSearchSubmitted);
    on<EventLoadMoreResults>(_onLoadMore);

    // Refresh results for current query on language change
    _langSub = AppEvents.languagesChanged.stream.listen((_) {
      final q = lastQuery?.trim();
      if (q != null && q.isNotEmpty) {
        add(EventSearchIconClicked(q));
      }
    });
  }

  Future<void> _onSearchSubmitted(
    EventSearchIconClicked event,
    Emitter<SearchState> emit,
  ) async {
    final query = event.searchQuery.trim();
    final generation = ++_generation;
    lastQuery = query;
    currentPage = 1;
    _loadingMore = false;
    _hasMore = true;
    if (query.isEmpty) {
      emit(SearchInitial());
      return;
    }
    emit(SearchLoading());
    await _runSearch(emit,
        query: query, page: 1, generation: generation, isFresh: true);
  }

  Future<void> _onLoadMore(
      EventLoadMoreResults event, Emitter<SearchState> emit) async {
    final query = lastQuery;
    if (query == null ||
        query.isEmpty ||
        _loadingMore ||
        !_hasMore ||
        state is! SearchSuccess) {
      return;
    }
    _loadingMore = true;
    final generation = _generation;
    await _runSearch(emit,
        query: query,
        page: currentPage + 1,
        generation: generation,
        isFresh: false);
    if (generation == _generation) _loadingMore = false;
  }

  Future<void> _runSearch(
    Emitter<SearchState> emit, {
    required String query,
    required int page,
    required int generation,
    required bool isFresh,
  }) async {
    try {
      final result = await _api.searchAudiobook(query, page, 10);
      if (generation != _generation || emit.isDone) return;
      result.fold((error) {
        if (isFresh) {
          emit(SearchFailure(error));
        } else if (state is SearchSuccess) {
          emit(SearchSuccess((state as SearchSuccess).audiobooks,
              hasMore: _hasMore, error: error));
        }
      }, (books) {
        currentPage = page;
        _hasMore = books.isNotEmpty;
        final previous = !isFresh && state is SearchSuccess
            ? (state as SearchSuccess).audiobooks
            : <Audiobook>[];
        final unique = {
          for (final book in [...previous, ...books]) book.id: book
        };
        emit(SearchSuccess(unique.values.toList(), hasMore: _hasMore));
      });
    } catch (_) {
      if (generation != _generation || emit.isDone) return;
      if (isFresh) {
        emit(SearchFailure('Failed to search audiobooks'));
      } else if (state is SearchSuccess) {
        emit(SearchSuccess((state as SearchSuccess).audiobooks,
            hasMore: _hasMore,
            error: 'Could not load more results. Scroll to retry.'));
      }
    }
  }

  @override
  Future<void> close() {
    _langSub?.cancel();
    return super.close();
  }
}
