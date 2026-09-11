part of 'search_bloc.dart';

@immutable
sealed class SearchState {}

final class SearchInitial extends SearchState {}

class SearchLoading extends SearchState {}

class SearchSuccess extends SearchState {
  final List<Audiobook> audiobooks;
  final bool hasMore;
  final String? error;
  SearchSuccess(this.audiobooks, {this.hasMore = true, this.error});
}

class SearchFailure extends SearchState {
  final String errorMessage;
  SearchFailure(this.errorMessage);
}
