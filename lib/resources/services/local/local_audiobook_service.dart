import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:aradia/resources/services/local/local_book_metadata.dart';
import 'package:hive/hive.dart';
import 'package:aradia/resources/models/local_audiobook.dart';
import 'package:aradia/utils/app_logger.dart';
import 'package:aradia/utils/media_helper.dart';
import 'package:saf/saf.dart';
// ignore: implementation_imports
import 'package:saf/src/storage_access_framework/api.dart';
import 'package:path/path.dart' as path;

class LocalAudiobookService {
  static const String _rootFolderKey = 'local_audiobooks_root_folder';
  static const String _audiobooksBoxName = 'local_audiobooks';
  static const String _fileCacheBoxName = 'local_audiobooks_file_cache';

  static Future<void> _replaceLibrary(
      Box<dynamic> box, List<LocalAudiobook> books) async {
    final entries = {for (final book in books) book.id: book.toMap()};
    // Write the replacement before removing stale records, so a failed write
    // cannot erase the existing library.
    await box.putAll(entries);
    await box
        .deleteAll(box.keys.where((key) => !entries.containsKey(key)).toList());
  }

  static Future<String?> getRootFolderPath() async {
    final box = await Hive.openBox('settings');
    return box.get(_rootFolderKey);
  }

  static Future<void> setRootFolderPath(String p) async {
    final box = await Hive.openBox('settings');
    await box.put(_rootFolderKey, p);
  }

  static Future<List<LocalAudiobook>> getAllAudiobooks() async {
    try {
      final box = await Hive.openBox(_audiobooksBoxName);
      final List<LocalAudiobook> audiobooks = [];
      for (final key in box.keys) {
        try {
          final map = Map<String, dynamic>.from(box.get(key));
          audiobooks.add(LocalAudiobook.fromMap(map));
        } catch (e) {
          AppLogger.error('Unable to read cached audiobook $key: $e');
        }
      }
      return LocalBookMetadata.apply(audiobooks);
    } catch (e) {
      AppLogger.error('Error getting audiobooks from Hive: $e');
      return [];
    }
  }

  static Future<void> saveAudiobook(LocalAudiobook audiobook) async {
    try {
      final box = await Hive.openBox(_audiobooksBoxName);
      await box.put(audiobook.id, audiobook.toMap());
    } catch (e) {
      AppLogger.error('Error saving audiobook to Hive: $e');
    }
  }

  static Future<void> updateAudiobook(LocalAudiobook audiobook) async {
    try {
      final box = await Hive.openBox(_audiobooksBoxName);
      await box.put(audiobook.id, audiobook.toMap());
    } catch (e) {
      AppLogger.error('Error updating audiobook in Hive: $e');
    }
  }

  static Future<void> deleteAudiobook(LocalAudiobook audiobook) async {
    try {
      final box = await Hive.openBox(_audiobooksBoxName);
      await box.delete(audiobook.id);
    } catch (e) {
      AppLogger.error('Error deleting audiobook from Hive: $e');
    }
  }

  /// Get the last scanned file paths from cache
  static Future<List<String>?> getLastScannedFiles() async {
    try {
      final box = await Hive.openBox(_fileCacheBoxName);
      final cacheData = box.get('file_cache');
      if (cacheData != null) {
        final map = Map<String, dynamic>.from(cacheData);
        return List<String>.from(map['file_paths'] ?? []);
      }
      return null;
    } catch (e) {
      AppLogger.error('Error getting last scanned files from cache: $e');
      return null;
    }
  }

  /// Save the scanned file paths to cache
  static Future<void> saveScannedFiles(List<String> files) async {
    try {
      final box = await Hive.openBox(_fileCacheBoxName);
      final cacheData = {
        'file_paths': files,
        'last_scan_time': DateTime.now().millisecondsSinceEpoch,
      };
      await box.put('file_cache', cacheData);
    } catch (e) {
      AppLogger.error('Error saving scanned files to cache: $e');
    }
  }

  /// Clear the file cache (useful when changing root folder)
  static Future<void> clearFileCache() async {
    try {
      final box = await Hive.openBox(_fileCacheBoxName);
      await box.clear();
    } catch (e) {
      AppLogger.error('Error clearing file cache: $e');
    }
  }

  /// Clear all audiobook caches (useful when changing root folder)
  static Future<void> clearAllCaches() async {
    MediaHelper.clearMetadataCache();
    await (await Hive.openBox('local_chapters_box')).clear();
    try {
      // Clear file cache
      await clearFileCache();

      // Clear audiobooks cache
      final audiobooksBox = await Hive.openBox(_audiobooksBoxName);
      await audiobooksBox.clear();

      AppLogger.info('Cleared all audiobook caches');
    } catch (e) {
      AppLogger.error('Error clearing all caches: $e');
    }
  }

  static Future<List<LocalAudiobook>> refreshAudiobooks() async {
    try {
      final scanned = await scanForAudiobooks();
      final box = await Hive.openBox(_audiobooksBoxName);
      await _replaceLibrary(box, scanned);
      return LocalBookMetadata.apply(scanned);
    } catch (e) {
      AppLogger.error('Error refreshing audiobooks: $e');
      return getAllAudiobooks();
    }
  }

  /// Smart refresh that only processes changed files
  static Future<List<LocalAudiobook>> smartRefreshAudiobooks() async {
    try {
      final rootFolderPath = await getRootFolderPath();
      if (rootFolderPath == null) {
        AppLogger.error('Root folder path is null');
        return [];
      }

      // Get current file list from SAF
      List<String>? currentFiles = await Saf.getFilesPathFor(rootFolderPath);
      if (currentFiles == null) {
        AppLogger.error('Failed to get files from root folder');
        return getAllAudiobooks();
      }

      // Get cached file list
      List<String>? cachedFiles = await getLastScannedFiles();

      // If no cache exists, do a full scan
      if (cachedFiles == null) {
        AppLogger.info('No cache found, performing full scan');
        final scanned = await scanForAudiobooks();
        AppLogger.info(
            'Full scan completed, found ${scanned.length} audiobooks');
        await saveScannedFiles(currentFiles);

        // Save all audiobooks to Hive
        final box = await Hive.openBox(_audiobooksBoxName);
        await _replaceLibrary(box, scanned);
        AppLogger.info('Saved ${scanned.length} audiobooks to Hive');

        return LocalBookMetadata.apply(scanned);
      }

      // Compare file lists to detect changes
      Set<String> currentFileSet = currentFiles.toSet();
      Set<String> cachedFileSet = cachedFiles.toSet();

      Set<String> newFiles = currentFileSet.difference(cachedFileSet);
      Set<String> deletedFiles = cachedFileSet.difference(currentFileSet);
      Set<String> changedFiles = newFiles.union(deletedFiles);

      AppLogger.info(
          'File changes detected: ${newFiles.length} new, ${deletedFiles.length} deleted');

      if (newFiles.isNotEmpty) {
        AppLogger.info(
            'New files: ${newFiles.take(5).join(', ')}${newFiles.length > 5 ? '...' : ''}');
      }
      if (deletedFiles.isNotEmpty) {
        AppLogger.info(
            'Deleted files: ${deletedFiles.take(5).join(', ')}${deletedFiles.length > 5 ? '...' : ''}');
      }

      // If no changes, return cached audiobooks
      if (changedFiles.isEmpty) {
        AppLogger.info('No file changes detected, returning cached audiobooks');
        await saveScannedFiles(currentFiles); // Update scan time
        return await getAllAudiobooks();
      }

      // Get affected audiobook IDs
      Set<String> affectedIds =
          _getAffectedAudiobookIds(changedFiles.toList(), rootFolderPath);
      AppLogger.info('Affected audiobook IDs: ${affectedIds.length}');
      if (affectedIds.isNotEmpty) {
        AppLogger.info('Affected IDs: ${affectedIds.join(', ')}');
      }

      // Get all current audiobooks from cache
      List<LocalAudiobook> allAudiobooks = await getAllAudiobooks();
      Map<String, LocalAudiobook> audiobookMap = {
        for (var a in allAudiobooks) a.id: a
      };

      // Remove deleted audiobooks
      for (String deletedFile in deletedFiles) {
        String? audiobookId =
            _getAudiobookIdForFile(deletedFile, rootFolderPath);
        if (audiobookId != null && audiobookMap.containsKey(audiobookId)) {
          // Check if this was the last file in the audiobook
          LocalAudiobook audiobook = audiobookMap[audiobookId]!;
          bool hasRemainingFiles = audiobook.audioFiles.any(
              (file) => currentFileSet.contains(file) && file != deletedFile);

          if (!hasRemainingFiles) {
            AppLogger.info('Removing deleted audiobook: $audiobookId');
            audiobookMap.remove(audiobookId);
            await deleteAudiobook(audiobook);
          }
        }
      }

      // Group once rather than walking the entire library for each changed book.
      final filesByBook = <String, List<String>>{};
      for (final file in currentFiles) {
        final id = _getAudiobookIdForFile(file, rootFolderPath);
        if (id != null && affectedIds.contains(id)) {
          filesByBook.putIfAbsent(id, () => []).add(file);
        }
      }
      // Process affected audiobooks
      for (String audiobookId in affectedIds) {
        AppLogger.info('Processing affected audiobook ID: $audiobookId');

        // Get files for this specific audiobook
        final audiobookFiles = filesByBook[audiobookId] ?? <String>[];

        AppLogger.info(
            'Found ${audiobookFiles.length} files for audiobook ID: $audiobookId');

        // Determine level and process accordingly
        if (audiobookFiles.isNotEmpty) {
          Map<String, dynamic> fileInfo =
              _getFileLevelAndFolder(audiobookFiles.first, rootFolderPath);
          int level = fileInfo['level'];

          AppLogger.info(
              'Processing level $level for audiobook ID: $audiobookId');

          LocalAudiobook? processedAudiobook = await _processSingleAudiobook(
              audiobookId, audiobookFiles, level, rootFolderPath);

          // Update or add the audiobook in our map
          if (processedAudiobook != null) {
            audiobookMap[audiobookId] = processedAudiobook;
            await updateAudiobook(processedAudiobook);
            AppLogger.info(
                'Updated/Added audiobook: ${processedAudiobook.title}');
          } else {
            AppLogger.warning('No audiobook processed for ID: $audiobookId');
          }
        } else {
          AppLogger.warning('No files found for audiobook ID: $audiobookId');
        }
      }

      // Save updated file list to cache
      await saveScannedFiles(currentFiles);

      // Return all audiobooks (updated + unchanged)
      return LocalBookMetadata.apply(audiobookMap.values.toList());
    } catch (e) {
      AppLogger.error('Error in smart refresh: $e');
      // Fallback to full scan
      return await refreshAudiobooks();
    }
  }

  /// Determine which audiobook IDs are affected by file changes
  static Set<String> _getAffectedAudiobookIds(
      List<String> changedFilePaths, String rootFolderPath) {
    Set<String> affectedIds = {};

    for (String filePath in changedFilePaths) {
      // Determine the level and get the audiobook ID
      String? audiobookId = _getAudiobookIdForFile(filePath, rootFolderPath);
      if (audiobookId != null) {
        affectedIds.add(audiobookId);
      }
    }

    return affectedIds;
  }

  /// Determine the audiobook ID for a given file based on its level
  static String? _getAudiobookIdForFile(
      String filePath, String rootFolderPath) {
    try {
      List<String> pathParts = filePath.split(rootFolderPath);
      if (pathParts.length < 2) return null;

      String relativePath = pathParts.last;
      List<String> pathPartsAfterRootFolder = relativePath.split("/");

      // Level 0: rootFolder/file (2 parts after root)
      if (pathPartsAfterRootFolder.length == 2) {
        return filePath; // Use file path as ID for level 0
      }

      // Level 1: rootFolder/subfolder/file (3 parts after root)
      if (pathPartsAfterRootFolder.length == 3) {
        String subfolder = pathPartsAfterRootFolder[1];
        return path.join(rootFolderPath, subfolder);
      }

      // Level 2: rootFolder/author/book/file (4 parts after root)
      if (pathPartsAfterRootFolder.length == 4) {
        String author = pathPartsAfterRootFolder[1];
        String book = pathPartsAfterRootFolder[2];
        return path.join(rootFolderPath, author, book);
      }

      return null;
    } catch (e) {
      AppLogger.error('Error determining audiobook ID for file $filePath: $e');
      return null;
    }
  }

  /// Get the level (0, 1, or 2) and folder path for a file
  static Map<String, dynamic> _getFileLevelAndFolder(
      String filePath, String rootFolderPath) {
    try {
      List<String> pathParts = filePath.split(rootFolderPath);
      if (pathParts.length < 2) {
        return {'level': -1, 'folder': null};
      }

      String relativePath = pathParts.last;
      List<String> pathPartsAfterRootFolder = relativePath.split("/");

      // Level 0: rootFolder/file (2 parts after root)
      if (pathPartsAfterRootFolder.length == 2) {
        return {'level': 0, 'folder': rootFolderPath};
      }

      // Level 1: rootFolder/subfolder/file (3 parts after root)
      if (pathPartsAfterRootFolder.length == 3) {
        String subfolder = pathPartsAfterRootFolder[1];
        return {'level': 1, 'folder': path.join(rootFolderPath, subfolder)};
      }

      // Level 2: rootFolder/author/book/file (4 parts after root)
      if (pathPartsAfterRootFolder.length == 4) {
        String author = pathPartsAfterRootFolder[1];
        String book = pathPartsAfterRootFolder[2];
        return {'level': 2, 'folder': path.join(rootFolderPath, author, book)};
      }

      return {'level': -1, 'folder': null};
    } catch (e) {
      AppLogger.error('Error determining file level for $filePath: $e');
      return {'level': -1, 'folder': null};
    }
  }

  /// Process a single audiobook based on its level and files
  static Future<LocalAudiobook?> _processSingleAudiobook(String audiobookId,
      List<String> audiobookFiles, int level, String rootFolderPath) async {
    try {
      if (level == 0) {
        // Level 0: Single file audiobook
        if (audiobookFiles.length == 1) {
          return await _processSingleLevel0Audiobook(
              audiobookFiles.first, rootFolderPath);
        }
      } else if (level == 1) {
        // Level 1: Single folder audiobook
        return await _processSingleLevel1Audiobook(
            audiobookId, audiobookFiles, rootFolderPath);
      } else if (level == 2) {
        // Level 2: Author/Book audiobook
        return await _processSingleLevel2Audiobook(
            audiobookId, audiobookFiles, rootFolderPath);
      }

      return null;
    } catch (e) {
      AppLogger.error('Error processing single audiobook $audiobookId: $e');
      return null;
    }
  }

  /// Process a single Level 0 audiobook
  static Future<LocalAudiobook?> _processSingleLevel0Audiobook(
      String filePath, String rootFolderPath) async {
    try {
      if (!await MediaHelper.isAudioFile(filePath)) {
        return null;
      }

      AppLogger.info('Processing single Level 0 audiobook: $filePath');

      // Extract metadata from the audio file
      Metadata metadata;
      try {
        metadata = await MediaHelper.getAudioMetadata(filePath, rootFolderPath)
            .timeout(const Duration(seconds: 60));
      } catch (timeoutError) {
        AppLogger.error('Metadata extraction timed out for: $filePath');
        metadata = Metadata(
          trackName: path.basenameWithoutExtension(filePath),
          albumName: path.basenameWithoutExtension(filePath),
          albumArtistName: 'Unknown',
          trackDuration: null,
          albumArt: null,
          filePath: filePath,
        );
      }

      // Get title and author from metadata
      String title = metadata.albumName ??
          metadata.trackName ??
          path.basenameWithoutExtension(filePath);
      String author = metadata.albumArtistName ??
          metadata.trackArtistNames?.join(', ') ??
          'Unknown';

      // Look for cover image with same name as audio file
      String? coverImagePath = await MediaHelper.findCoverImageForAudioFile(
          filePath, rootFolderPath);

      // If no cover image found, try to extract from metadata
      if (coverImagePath == null && metadata.albumArt != null) {
        coverImagePath = await MediaHelper.saveAlbumArtFromMetadata(
            metadata.albumArt!, path.basenameWithoutExtension(filePath));
      }

      // Create the audiobook object
      return LocalAudiobook(
        id: filePath,
        title: title,
        author: author,
        folderPath: rootFolderPath,
        coverImagePath: coverImagePath,
        audioFiles: [filePath],
        totalDuration: metadata.trackDuration != null
            ? Duration(milliseconds: metadata.trackDuration!)
            : null,
        dateAdded: DateTime.now(),
        lastModified: DateTime.now(),
        description: metadata.authorName ?? metadata.writerName,
        genre: metadata.genre,
      );
    } catch (e) {
      AppLogger.error(
          'Error processing single Level 0 audiobook $filePath: $e');
      return null;
    }
  }

  /// Process a single Level 1 audiobook
  static Future<LocalAudiobook?> _processSingleLevel1Audiobook(
      String audiobookId,
      List<String> audiobookFiles,
      String rootFolderPath) async {
    try {
      // Filter audio files
      List<String> audioFiles = [];
      for (String filePath in audiobookFiles) {
        if (await MediaHelper.isAudioFile(filePath)) {
          audioFiles.add(filePath);
        }
      }

      if (audioFiles.isEmpty) return null;

      // Extract folder name from audiobook ID
      String subfolder = path.basename(audiobookId);
      String title = MediaHelper.capitalizeWords(subfolder);
      String author = 'Unknown';

      // Find cover image in the subfolder
      String? coverImagePath = await MediaHelper.findCoverImageInFolder(
          audiobookFiles, subfolder, rootFolderPath);

      // If no cover found, try to extract from first audio file metadata
      if (coverImagePath == null && audioFiles.isNotEmpty) {
        coverImagePath = await MediaHelper.extractCoverFromAudioMetadata(
            audioFiles.first, rootFolderPath, subfolder);
      }

      // Calculate total duration from all audio files
      Duration? totalDuration =
          await MediaHelper.calculateTotalDuration(audioFiles, rootFolderPath);

      // Create the audiobook object
      return LocalAudiobook(
        id: audiobookId,
        title: title,
        author: author,
        folderPath: audiobookId,
        coverImagePath: coverImagePath,
        audioFiles: audioFiles,
        totalDuration: totalDuration,
        dateAdded: DateTime.now(),
        lastModified: DateTime.now(),
      );
    } catch (e) {
      AppLogger.error(
          'Error processing single Level 1 audiobook $audiobookId: $e');
      return null;
    }
  }

  /// Process a single Level 2 audiobook
  static Future<LocalAudiobook?> _processSingleLevel2Audiobook(
      String audiobookId,
      List<String> audiobookFiles,
      String rootFolderPath) async {
    try {
      // Filter audio files
      List<String> audioFiles = [];
      for (String filePath in audiobookFiles) {
        if (await MediaHelper.isAudioFile(filePath)) {
          audioFiles.add(filePath);
        }
      }

      if (audioFiles.isEmpty) return null;

      // Extract author and book from audiobook ID
      String relativePath = audiobookId.replaceFirst(rootFolderPath, '');
      List<String> pathParts =
          relativePath.split('/').where((s) => s.isNotEmpty).toList();

      if (pathParts.length < 2) return null;

      String author = pathParts[0];
      String book = pathParts[1];
      String title = MediaHelper.capitalizeWords(book);
      String authorName = MediaHelper.capitalizeWords(author);

      // Find cover image in the book folder
      String? coverImagePath = await MediaHelper.findCoverImageInFolder(
          audiobookFiles, book, rootFolderPath);

      // If no cover found, try to extract from first audio file metadata
      if (coverImagePath == null && audioFiles.isNotEmpty) {
        coverImagePath = await MediaHelper.extractCoverFromAudioMetadata(
            audioFiles.first, rootFolderPath, book);
      }

      // Calculate total duration from all audio files
      Duration? totalDuration =
          await MediaHelper.calculateTotalDuration(audioFiles, rootFolderPath);

      // Create the audiobook object
      return LocalAudiobook(
        id: audiobookId,
        title: title,
        author: authorName,
        folderPath: audiobookId,
        coverImagePath: coverImagePath,
        audioFiles: audioFiles,
        totalDuration: totalDuration,
        dateAdded: DateTime.now(),
        lastModified: DateTime.now(),
      );
    } catch (e) {
      AppLogger.error(
          'Error processing single Level 2 audiobook $audiobookId: $e');
      return null;
    }
  }

  // Here we scan each level of the audiobook tree and return all the audiobooks
  static Future<List<LocalAudiobook>> scanForAudiobooks() async {
    final rootFolderPath = await getRootFolderPath();
    if (rootFolderPath == null) {
      AppLogger.error('Root folder path is null');
      throw StateError('No audiobook folder selected.');
    }

    List<String>? allFilesInsideRootFolder =
        await Saf.getFilesPathFor(rootFolderPath);

    if (allFilesInsideRootFolder == null) {
      AppLogger.error('Failed to get files from root folder');
      throw StateError('The audiobook folder is unavailable.');
    }

    AppLogger.info(
        'Found ${allFilesInsideRootFolder.length} files in root folder');

    List<LocalAudiobook> allAudiobooks = [];

    // Level 0: Standalone audiobooks (files directly in root)
    List<LocalAudiobook> level0Audiobooks =
        await processLevel0Audiobooks(rootFolderPath, allFilesInsideRootFolder);
    allAudiobooks.addAll(level0Audiobooks);

    // delete cache
    await Saf.clearCacheFor(rootFolderPath);

    // Level 1: Single subfolder audiobooks
    List<LocalAudiobook> level1Audiobooks =
        await processLevel1Audiobooks(rootFolderPath, allFilesInsideRootFolder);
    allAudiobooks.addAll(level1Audiobooks);

    await Saf.clearCacheFor(rootFolderPath);

    // Level 2: Two subfolder audiobooks
    List<LocalAudiobook> level2Audiobooks =
        await processLevel2Audiobooks(rootFolderPath, allFilesInsideRootFolder);
    allAudiobooks.addAll(level2Audiobooks);

    await Saf.clearCacheFor(rootFolderPath);

    // Save the scanned file list to cache
    await saveScannedFiles(allFilesInsideRootFolder);

    return LocalBookMetadata.apply(allAudiobooks);
  }

  static Future<List<LocalAudiobook>> processLevel0Audiobooks(
          String rootFolderPath, List<String> files) =>
      _processLevel(rootFolderPath, files, 0);

  static Future<List<LocalAudiobook>> processLevel1Audiobooks(
          String rootFolderPath, List<String> files) =>
      _processLevel(rootFolderPath, files, 1);

  static Future<List<LocalAudiobook>> processLevel2Audiobooks(
          String rootFolderPath, List<String> files) =>
      _processLevel(rootFolderPath, files, 2);

  /// Full and incremental scans share the same metadata extraction logic.
  static Future<List<LocalAudiobook>> _processLevel(
      String rootFolderPath, List<String> files, int level) async {
    final permitted = await Saf.isPersistedPermissionDirectoryFor(
        makeUriString(path: rootFolderPath, isTreeUri: true));
    if (permitted != true) {
      throw StateError('No permission to access the audiobook folder.');
    }
    final groups = <String, List<String>>{};
    for (final file in files) {
      if (_getFileLevelAndFolder(file, rootFolderPath)['level'] != level) {
        continue;
      }
      final id = _getAudiobookIdForFile(file, rootFolderPath);
      if (id != null) groups.putIfAbsent(id, () => []).add(file);
    }
    final books = <LocalAudiobook>[];
    Iterable<MapEntry<String, List<String>>> ordered = groups.entries;
    if (level == 2) {
      // Preserve the existing author-then-book shelf order.
      final authors = <String, List<MapEntry<String, List<String>>>>{};
      for (final group in groups.entries) {
        authors.putIfAbsent(path.dirname(group.key), () => []).add(group);
      }
      ordered = authors.values.expand((books) => books);
    }
    for (final group in ordered) {
      final book = await _processSingleAudiobook(
          group.key, group.value, level, rootFolderPath);
      if (book != null) books.add(book);
    }
    return books;
  }
}
