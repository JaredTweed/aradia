import 'dart:convert';
import 'dart:io';
import 'package:aradia/utils/app_logger.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:aradia/utils/permission_helper.dart';
import 'chapter_downloads.dart';

class DownloadManager {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;
  DownloadManager._internal();

  final FileDownloader _downloader = FileDownloader();
  final Box<dynamic> downloadStatusBox = Hive.box('download_status_box');
  final Map<String, bool> _activeDownloads = {};
  final Map<String, DownloadTask> _currentTasks = {};

  Future<bool> checkAndRequestPermissions() =>
      PermissionHelper.requestDownloadPermissions();

  Future<void> downloadAudiobook(
    String audiobookId,
    String audiobookTitle,
    List<Map<String, dynamic>> files,
    Function(double) onProgressUpdate,
    Function(bool) onCompleted,
  ) async {
    if (_activeDownloads.containsKey(audiobookId)) return;
    _activeDownloads[audiobookId] = true;
    double progress = 0;
    bool completed = false;
    int downloadedCount = 0;
    int? totalCount;
    final statusKey = 'status_$audiobookId';
    Map<String, dynamic> status({String? error}) => {
          'audiobookId': audiobookId,
          'audiobookTitle': audiobookTitle,
          'isDownloading': !completed && error == null,
          'isCompleted': completed,
          'progress': progress,
          'downloadedCount': downloadedCount,
          if (totalCount != null) 'totalCount': totalCount,
          if (error != null) 'error': error,
          if (completed) 'downloadDate': DateTime.now().toIso8601String(),
        };

    try {
      await downloadStatusBox.put(statusKey, status());
      if (files.isEmpty) throw StateError('No audio files to download.');
      final baseDir = await getExternalStorageDirectory();
      if (baseDir == null) throw StateError('Download storage is unavailable.');
      final directory = Directory('${baseDir.path}/downloads/$audiobookId');
      await directory.create(recursive: true);
      final catalogue = File('${directory.path}/catalogue.json');
      if (await catalogue.exists()) {
        totalCount =
            (jsonDecode(await catalogue.readAsString()) as List).length;
      }
      final saved = await ChapterDownloads.completed(directory);
      final savedUrls = saved.map((e) => e['url']).toSet();
      downloadedCount = saved.length;
      final hasNotifications = await checkAndRequestPermissions();
      await _downloader.configure(
        androidConfig: [(Config.useExternalStorage, Config.always)],
      );
      if (hasNotifications) {
        _downloader.configureNotification(
          running: TaskNotification(
              'Downloading $audiobookTitle', 'File: {filename}'),
          progressBar: true,
          complete: TaskNotification(
              'Download complete: $audiobookTitle', 'File: {filename}'),
          error: TaskNotification(
              'Download error: $audiobookTitle', 'File: {filename}'),
        );
      }
      for (var i = 0; i < files.length; i++) {
        if (_activeDownloads[audiobookId] != true) break;
        if (savedUrls.contains(files[i]['url'])) {
          progress = (i + 1) / files.length;
          onProgressUpdate(progress);
          continue;
        }
        final url = files[i]['url'] as String?;
        final uri = url == null ? null : Uri.tryParse(url);
        if (uri == null ||
            !['http', 'https'].contains(uri.scheme) ||
            uri.host.isEmpty) {
          throw FormatException('Invalid audio download URL.');
        }
        // Numbered names preserve chapter order and cannot collide or contain path separators.
        final title = (files[i]['title'] as String? ?? 'Chapter')
            .replaceAll(RegExp(r'[\/:*?"<>|]'), '_');
        final shortTitle = title.length > 100 ? title.substring(0, 100) : title;
        final filename = files[i]['filename'] as String? ??
            '${(i + 1).toString().padLeft(5, '0')}-$shortTitle.mp3';
        final entry = {
          ...files[i],
          'filename': filename,
          'order': files[i]['order'] ?? i
        };
        final task = DownloadTask(
          taskId: '$audiobookId-$i',
          url: url!,
          filename: '$filename.part',
          directory: 'downloads/$audiobookId',
          baseDirectory: BaseDirectory.applicationDocuments,
          updates: Updates.statusAndProgress,
        );
        _currentTasks[audiobookId] = task;
        await downloadStatusBox.put('task_${task.taskId}', task.toJson());
        final result = await _downloader.download(task, onProgress: (value) {
          if (_activeDownloads[audiobookId] != true || value < 0) return;
          progress = (i + value.clamp(0.0, 1.0)) / files.length;
          onProgressUpdate(progress);
          downloadStatusBox.put(statusKey, status());
        });
        await downloadStatusBox.delete('task_${task.taskId}');
        _currentTasks.remove(audiobookId);
        if (result.status == TaskStatus.complete) {
          await File('${directory.path}/$filename.part')
              .rename('${directory.path}/$filename');
          await ChapterDownloads.record(directory, entry);
          downloadedCount++;
        } else {
          final incomplete = File('${directory.path}/$filename.part');
          if (await incomplete.exists()) await incomplete.delete();
        }
        if (_activeDownloads[audiobookId] != true) break;
        if (result.status != TaskStatus.complete) {
          throw StateError('Download failed for $shortTitle. Please retry.');
        }
        progress = (i + 1) / files.length;
        onProgressUpdate(progress);
      }
      if (_activeDownloads[audiobookId] == true) {
        completed = true;
        await downloadStatusBox.put(statusKey, status());
      }
    } catch (e) {
      AppLogger.debug('Download error: $e');
      if (_activeDownloads[audiobookId] == true) {
        await downloadStatusBox.put(statusKey, status(error: e.toString()));
      }
    } finally {
      final task = _currentTasks.remove(audiobookId);
      if (task != null) await downloadStatusBox.delete('task_${task.taskId}');
      if (_activeDownloads[audiobookId] == false) {
        await downloadStatusBox.put(
            statusKey,
            status(
                error:
                    'Download cancelled. Completed chapters are kept; retry to continue.'));
      }
      _activeDownloads.remove(audiobookId);
    }
    onCompleted(completed);
  }

  Future<void> _cleanupPartialDownload(String audiobookId) async {
    try {
      final baseDir = await getExternalStorageDirectory();
      if (baseDir == null) return;
      final directory = Directory('${baseDir.path}/downloads/$audiobookId');
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (e) {
      AppLogger.debug('Download cleanup error: $e');
    }
  }

  Future<void> cancelDownload(String audiobookId) async {
    if (_activeDownloads.containsKey(audiobookId)) {
      _activeDownloads[audiobookId] = false;
      final task = _currentTasks[audiobookId];
      if (task != null) await _downloader.cancelTaskWithId(task.taskId);
    } else {
      await _cleanupPartialDownload(audiobookId);
      await downloadStatusBox.delete('status_$audiobookId');
    }
  }

  bool isDownloading(String audiobookId) {
    final status = downloadStatusBox.get('status_$audiobookId');
    return _activeDownloads[audiobookId] == true ||
        (status != null && status['isDownloading'] == true);
  }

  bool isDownloaded(String audiobookId) {
    final status = downloadStatusBox.get('status_$audiobookId');
    return status != null && status['isCompleted'] == true;
  }

  double getProgress(String audiobookId) {
    final status = downloadStatusBox.get('status_$audiobookId');
    return status != null
        ? (status['progress'] as num?)?.toDouble() ?? 0.0
        : 0.0;
  }

  String? getError(String audiobookId) {
    final status = downloadStatusBox.get('status_$audiobookId');
    return status != null ? status['error'] as String? : null;
  }

  Future<void> retryDownload(String audiobookId) async {
    final status = downloadStatusBox.get('status_$audiobookId');
    if (status == null || _activeDownloads.containsKey(audiobookId)) return;
    final baseDir = await getExternalStorageDirectory();
    if (baseDir == null) throw StateError('Download storage is unavailable.');
    final metadata = File('${baseDir.path}/downloads/$audiobookId/files.txt');
    if (!await metadata.exists()) {
      throw StateError(
          'Open this book and download it again to restore its download details.');
    }
    final files = (jsonDecode(await metadata.readAsString()) as List)
        .map((file) => Map<String, dynamic>.from(file as Map))
        .toList();
    await downloadAudiobook(
        audiobookId, status['audiobookTitle'] as String, files, (_) {}, (_) {});
  }
}
