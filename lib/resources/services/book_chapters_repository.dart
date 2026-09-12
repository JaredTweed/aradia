import 'dart:convert';
import 'dart:io';
import 'package:aradia/resources/archive_api.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/resources/services/download/chapter_downloads.dart';
import 'package:aradia/resources/services/local/local_book_library.dart';
import 'package:aradia/utils/app_logger.dart';
import 'package:path_provider/path_provider.dart';

class BookChapters {
  final List<AudiobookFile> playable;
  final List<AudiobookFile>? catalogue;
  const BookChapters(this.playable, {this.catalogue});
}

/// Resolves the full catalogue and overlays audio available on this device.
/// Widgets and blocs do not need to know the download storage format.
class BookChaptersRepository {
  Future<BookChapters> load(String id,
      {required bool isLocal,
      required bool isDownload,
      List<AudiobookFile>? fallback}) async {
    if (isLocal) {
      return BookChapters(
          await LocalBookLibrary.filesForId(id, fallback: fallback));
    }
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
      if (catalogue != null && cached != null && await directory!.exists()) {
        try {
          await cached.writeAsString(jsonEncode([
            for (var i = 0; i < catalogue.length; i++)
              ChapterDownloads.entry(catalogue[i], i)
          ]));
        } on FileSystemException catch (e) {
          // Cache write failure must not make a playable book unavailable.
          AppLogger.debug('Unable to cache chapter catalogue: $e');
        }
      }
    }
    if (catalogue != null && catalogue.isNotEmpty) {
      return BookChapters(
          directory == null
              ? catalogue
              : await ChapterDownloads.withDownloadedFiles(
                  directory, catalogue),
          catalogue: catalogue);
    }
    if (isDownload) {
      final offline = await AudiobookFile.fromDownloadedFiles(id);
      return offline.fold(
          (error) => throw StateError(error), (files) => BookChapters(files));
    }
    throw StateError('Unable to load chapters');
  }
}
