part of 'genre_audiobooks_bloc.dart';

@immutable
sealed class GenreAudiobooksEvent {}

class LoadInitialAudiobooksEvent extends GenreAudiobooksEvent {
  final String genre;
  final String listType;
  final bool refresh;

  LoadInitialAudiobooksEvent({
    required this.genre,
    required this.listType,
    this.refresh = false,
  });
}

class LoadMoreAudiobooksEvent extends GenreAudiobooksEvent {
  final String genre;
  final String listType;

  LoadMoreAudiobooksEvent({
    required this.genre,
    required this.listType,
  });
}
