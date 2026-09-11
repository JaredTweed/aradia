import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:aradia/resources/services/download/chapter_downloads.dart';

import 'package:aradia/utils/app_logger.dart';
import 'package:bloc/bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hive/hive.dart';
import 'package:aradia/resources/archive_api.dart';
import 'package:aradia/resources/services/local/local_book_library.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:meta/meta.dart';

part 'audiobook_details_event.dart';
part 'audiobook_details_state.dart';

class AudiobookDetailsBloc
    extends Bloc<AudiobookDetailsEvent, AudiobookDetailsState> {
  StreamSubscription? _favouriteBoxSubscription;
  Audiobook? _currentAudiobook;
  AudiobookDetailsBloc() : super(AudiobookDetailsInitial()) {
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
    Either<String, List<AudiobookFile>> audiobookFiles;
    try {
      if (isLocal) {
        audiobookFiles =
            Right(await LocalBookLibrary.filesForId(id, fallback: event.files));
      } else {
        final base = await getExternalStorageDirectory();
        final directory =
            base == null ? null : Directory('${base.path}/downloads/$id');
        final cached =
            directory == null ? null : File('${directory.path}/catalogue.json');
        List<AudiobookFile>? catalogue;
        if (cached != null && await cached.exists()) {
          try {
            catalogue = (jsonDecode(await cached.readAsString()) as List)
                .map((item) => AudiobookFile.fromMap(item as Map))
                .toList();
          } catch (e) {
            AppLogger.debug('Unable to read chapter catalogue: $e');
          }
        }
        if (catalogue == null || catalogue.isEmpty) {
          final remote = await ArchiveApi().getAudiobookFiles(id);
          catalogue = remote.fold((_) => null, (files) => files);
          if (catalogue != null &&
              cached != null &&
              await directory!.exists()) {
            await cached.writeAsString(jsonEncode([
              for (var i = 0; i < catalogue.length; i++)
                ChapterDownloads.entry(catalogue[i], i)
            ]));
          }
        }
        if (catalogue != null && catalogue.isNotEmpty) {
          final playable = directory == null
              ? catalogue
              : await ChapterDownloads.withDownloadedFiles(
                  directory, catalogue);
          emit(AudiobookDetailsLoaded(playable, catalogue: catalogue));
          return;
        }
        audiobookFiles = isDownload
            ? await AudiobookFile.fromDownloadedFiles(id)
            : const Left('Unable to load chapters');
      }

      audiobookFiles.fold((l) {
        emit(AudiobookDetailsError());
      }, (r) {
        emit(AudiobookDetailsLoaded([...r]));
      });
    } catch (e) {
      AppLogger.debug('Error coming from fetchAudiobookDetails bloc: $e');
      emit(AudiobookDetailsError());
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
