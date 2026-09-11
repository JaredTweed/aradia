part of 'audiobook_details_bloc.dart';

@immutable
sealed class AudiobookDetailsEvent {}

class FetchAudiobookDetails extends AudiobookDetailsEvent {
  final String audiobookId;
  final bool isDownload;
  final bool isLocal;
  final List<AudiobookFile>? files;

  FetchAudiobookDetails(
    this.audiobookId,
    this.isDownload,
    this.isLocal, {
    this.files,
  });
}

class FavouriteIconButtonClicked extends AudiobookDetailsEvent {
  final Audiobook audiobook;

  FavouriteIconButtonClicked(this.audiobook);
}

class GetFavouriteStatus extends AudiobookDetailsEvent {
  final Audiobook audiobook;

  GetFavouriteStatus(this.audiobook);
}
