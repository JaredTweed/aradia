import 'dart:async';
import 'package:aradia/resources/services/book_chapters_repository.dart';

import 'package:aradia/utils/app_logger.dart';
import 'package:bloc/bloc.dart';
import 'package:hive/hive.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:meta/meta.dart';

part 'audiobook_details_event.dart';
part 'audiobook_details_state.dart';

class AudiobookDetailsBloc
    extends Bloc<AudiobookDetailsEvent, AudiobookDetailsState> {
  StreamSubscription? _favouriteBoxSubscription;
  Audiobook? _currentAudiobook;
  final BookChaptersRepository _repository;
  int _generation = 0;
  AudiobookDetailsBloc({BookChaptersRepository? repository})
      : _repository = repository ?? BookChaptersRepository(),
        super(AudiobookDetailsInitial()) {
    on<FetchAudiobookDetails>((event, emit) => fetchAudiobookDetails(
          event,
          emit,
          event.audiobookId,
          event.isDownload,
          event.isLocal,
        ));
    on<FavouriteIconButtonClicked>(favouriteIconButtonClicked);

    on<GetFavouriteStatus>(getFavouriteStatus);

    final box = Hive.box('favourite_audiobooks_box');
    _favouriteBoxSubscription = box.watch().listen((event) {
      if (_currentAudiobook != null && event.key == _currentAudiobook!.id) {
        add(GetFavouriteStatus(_currentAudiobook!));
      }
    });
  }

  FutureOr<void> fetchAudiobookDetails(
    FetchAudiobookDetails event,
    Emitter<AudiobookDetailsState> emit,
    String id,
    bool isDownload,
    bool isLocal,
  ) async {
    emit(AudiobookDetailsLoading());
    AppLogger.debug('fetching audiobook details for id: $id');
    AppLogger.debug('isDownload: $isDownload');
    AppLogger.debug('isLocal: $isLocal');
    final generation = ++_generation;
    try {
      final chapters = await _repository.load(id,
          isLocal: isLocal, isDownload: isDownload, fallback: event.files);
      if (generation != _generation || emit.isDone) return;
      emit(AudiobookDetailsLoaded(chapters.playable,
          catalogue: chapters.catalogue));
    } catch (e) {
      AppLogger.debug('Error loading audiobook details: $e');
      if (generation == _generation && !emit.isDone) {
        emit(AudiobookDetailsError());
      }
    }
  }

  FutureOr<void> getFavouriteStatus(
    GetFavouriteStatus event,
    Emitter<AudiobookDetailsState> emit,
  ) async {
    _currentAudiobook = event.audiobook;
    var box = Hive.box('favourite_audiobooks_box');
    emit(AudiobookDetailsFavourite(box.containsKey(event.audiobook.id)));
  }

  FutureOr<void> favouriteIconButtonClicked(
    FavouriteIconButtonClicked event,
    Emitter<AudiobookDetailsState> emit,
  ) async {
    var box = Hive.box('favourite_audiobooks_box');
    _currentAudiobook = event.audiobook;
    AppLogger.debug('Favourite icon clicked and id is ${event.audiobook.id}');

    if (box.containsKey(event.audiobook.id)) {
      await box.delete(event.audiobook.id);
      AppLogger.debug('Favourite removed for this id ${event.audiobook.id}');
      emit(AudiobookDetailsFavourite(false));
    } else {
      await box.put(event.audiobook.id, event.audiobook.toMap());
      AppLogger.debug('Favourite added for this id ${event.audiobook.id}');
      emit(AudiobookDetailsFavourite(true));
    }
  }

  @override
  Future<void> close() {
    _favouriteBoxSubscription?.cancel();
    return super.close();
  }
}
