import 'package:aradia/resources/services/download/chapter_downloads.dart';
import 'dart:convert';
import 'dart:io';

import 'package:aradia/utils/app_logger.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:fpdart/fpdart.dart';
import 'package:path_provider/path_provider.dart';

const String _base = "https://archive.org/download";

class AudiobookFile {
  final String? identifier;
  final String? title;
  final String? name;
  final String? url;
  final double? length; // seconds
  final int? track;
  final int? size;
  final String? highQCoverImage;

  final int? startMs; // chapter start (ms from file start)
  final int? durationMs; // chapter duration (ms); null => to EOF

  Duration? get duration {
    if (durationMs != null && durationMs! > 0) {
      return Duration(milliseconds: durationMs!);
    }
    if (length != null && length! > 0) {
      return Duration(milliseconds: (length! * 1000).round());
    }
    return null;
  }

  String get durationLabel {
    final value = duration;
    if (value == null) return 'Duration unavailable';
    final seconds = value.inSeconds;
    final minutes = (seconds ~/ 60).toString();
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    if (seconds < 3600) return '$minutes:$remainder';
    return '${value.inHours}:${(value.inMinutes % 60).toString().padLeft(2, '0')}:$remainder';
  }

  AudiobookFile.fromJson(Map json)
      : identifier = json["identifier"]?.toString(),
        title = json["title"]?.toString(),
        name = json["name"]?.toString(),
        track = _parseTrack(json["track"]),
        size = _parseIntSafely(json["size"]),
        length = _parseDoubleSafely(json["length"]),
        url =
            "$_base/${Uri.encodeComponent(json['identifier'].toString())}/${Uri.encodeComponent(json['name'].toString())}",
        highQCoverImage = json["highQCoverImage"] == null
            ? null
            : "$_base/${Uri.encodeComponent(json['identifier'].toString())}/${Uri.encodeComponent(json["highQCoverImage"].toString())}",
        startMs = null,
        durationMs = null;

  AudiobookFile.fromLocalJson(Map json, String location)
      : identifier = json["identifier"]?.toString(),
        title = json["title"]?.toString(),
        name = json["name"]?.toString(),
        track = _parseTrack(json["track"]),
        size = _parseIntSafely(json["size"]),
        length = _parseDoubleSafely(json["length"]),
        url = "$location/${json["url"]!}",
        highQCoverImage = "$location/cover.jpg",
        startMs = null,
        durationMs = null;

  static AudiobookFile chapterSlice({
    required String identifier,
    required String url,
    required String parentTitle,
    required int track,
    required String chapterTitle,
    required int startMs,
    int? durationMs,
    String? highQCoverImage,
  }) {
    return AudiobookFile.fromMap({
      "identifier": identifier,
      "title": chapterTitle.isNotEmpty
          ? chapterTitle
          : "$parentTitle — Chapter $track",
      "name": parentTitle,
      "track": track,
      "size": 0,
      "length": durationMs == null ? null : durationMs / 1000,
      "url": url,
      "highQCoverImage": highQCoverImage,
      "startMs": startMs,
      "durationMs": durationMs,
    });
  }

  static int _parseTrack(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;

    try {
      final trackStr = value.toString();
      return int.parse(trackStr.split("/")[0]);
    } catch (e) {
      AppLogger.debug('Error parsing track value: $value, error: $e');
      return 0;
    }
  }

  static int _parseIntSafely(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;

    try {
      return int.parse(value.toString());
    } catch (e) {
      AppLogger.debug('Error parsing int value: $value, error: $e');
      return 0;
    }
  }

  static double _parseDoubleSafely(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();

    try {
      final text = value.toString();
      if (text.contains(':')) {
        return text.split(':').fold<double>(
            0, (seconds, part) => seconds * 60 + double.parse(part));
      }
      return double.parse(text);
    } catch (e) {
      AppLogger.debug('Error parsing double value: $value, error: $e');
      return 0.0;
    }
  }

  static List<AudiobookFile> fromJsonArray(List jsonFiles) {
    List<AudiobookFile> audiobookFiles = <AudiobookFile>[];
    for (var i = 0; i < jsonFiles.length; i++) {
      try {
        var jsonFile = jsonFiles[i];
        audiobookFiles.add(AudiobookFile.fromJson(jsonFile));
      } catch (e) {
        AppLogger.debug('Error parsing file at index $i: $e');
        AppLogger.debug('Data: ${jsonFiles[i]}');
      }
    }
    return audiobookFiles;
  }

  static List<AudiobookFile> fromLocalJsonArray(
      List jsonFiles, String location) {
    List<AudiobookFile> audiobookFiles = <AudiobookFile>[];
    for (var i = 0; i < jsonFiles.length; i++) {
      audiobookFiles.add(AudiobookFile.fromLocalJson(jsonFiles[i], location));
    }
    return audiobookFiles;
  }

  static Future<Either<String, List<AudiobookFile>>> fromDownloadedFiles(
      String audiobookId) async {
    try {
      final appDir = await getExternalStorageDirectory();
      final downloadDir = Directory('${appDir?.path}/downloads/$audiobookId');
      final manifest = await ChapterDownloads.completed(downloadDir);
      final savedChapters = manifest
          .map((entry) => AudiobookFile.fromMap({
                ...entry,
                'identifier': audiobookId,
                'url': '${downloadDir.path}/${entry['filename']}',
                'name': entry['filename'],
                'track': (entry['order'] as int) + 1,
              }))
          .toList();
      final savedNames = manifest.map((entry) => entry['filename']).toSet();
      List<FileSystemEntity> files = downloadDir
          .listSync()
          .where((file) =>
              file.path.endsWith('.mp3') &&
              !savedNames.contains(file.path.split('/').last))
          .toList();
      final numbered = files.every(
          (file) => RegExp(r'^\d{5}-').hasMatch(file.path.split('/').last));
      files.sort(numbered
          ? (a, b) => a.path.compareTo(b.path)
          : (a, b) => a.statSync().changed.compareTo(b.statSync().changed));

      AppLogger.debug(
          'Now the files are going to be parsed from the downloaded files');

      List<AudiobookFile> audiobookFiles = [...savedChapters];

      for (var i = 0; i < files.length; i++) {
        try {
          final metadata =
              await MetadataRetriever.fromFile(File(files[i].path));
          final duration = metadata.trackDuration?.toDouble() ?? 0.0;

          audiobookFiles.add(AudiobookFile.fromMap({
            "identifier": audiobookId,
            "title": files[i]
                .path
                .split('/')
                .last
                .replaceFirst(RegExp(r'\.mp3$'), '')
                .replaceFirst(RegExp(r'^\d{5}-'), ''),
            "name": files[i].path.split('/').last,
            "track": i + 1,
            "size": files[i].statSync().size,
            "length": duration / 1000, // Convert milliseconds to seconds
            "url": files[i].path,
            "highQCoverImage":
                'https://archive.org/services/get-item-image.php?identifier=$audiobookId',
          }));
        } catch (e) {
          AppLogger.debug('Error getting metadata for ${files[i].path}: $e');
          audiobookFiles.add(AudiobookFile.fromMap({
            "identifier": audiobookId,
            "title": files[i]
                .path
                .split('/')
                .last
                .replaceFirst(RegExp(r'\.mp3$'), '')
                .replaceFirst(RegExp(r'^\d{5}-'), ''),
            "name": files[i].path.split('/').last,
            "track": i + 1,
            "size": files[i].statSync().size,
            "length": 0.0,
            "url": files[i].path,
            "highQCoverImage":
                'https://archive.org/services/get-item-image.php?identifier=$audiobookId',
          }));
        }
      }

      if (manifest.isNotEmpty || numbered) {
        audiobookFiles.sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
      }
      return Right(audiobookFiles);
    } catch (e) {
      AppLogger.debug('Unexpected error: $e');
      return Left('Unexpected error: $e');
    }
  }

  static Future<Either<String, List<AudiobookFile>>> fromLocalFiles(
      String audiobookId) async {
    try {
      final appDir = await getExternalStorageDirectory();
      final downloadDir = Directory('${appDir?.path}/local/$audiobookId');

      final stringContent =
          await File('${downloadDir.path}/files.txt').readAsString();
      final jsonContent = jsonDecode(stringContent);
      if (jsonContent is List) {
        AppLogger.debug('JSON list length: ${jsonContent.length}');
        if (jsonContent.isNotEmpty) {
          AppLogger.debug('First item sample fields:');
          final item = jsonContent[0];
          if (item is Map) {
            item.forEach((key, value) {
              AppLogger.debug('  $key: $value (${value.runtimeType})');
            });
          }
        }
      }

      final List<AudiobookFile> audiobookFiles =
          AudiobookFile.fromLocalJsonArray(jsonContent, downloadDir.path);
      return Right(audiobookFiles);
    } catch (e) {
      AppLogger.debug('Unexpected error: $e');
      return Left('Unexpected error: $e');
    }
  }

  AudiobookFile.fromMap(Map<dynamic, dynamic> map)
      : identifier = map["identifier"],
        title = map["title"],
        name = map["name"],
        track = map["track"],
        size = map["size"],
        length = _parseDoubleSafely(map["length"]),
        url = map["url"],
        highQCoverImage = map["highQCoverImage"],
        startMs = map["startMs"],
        durationMs = map["durationMs"];

  Map<dynamic, dynamic> toMap() {
    return {
      "identifier": identifier,
      "title": title,
      "name": name,
      "track": track,
      "size": size,
      "length": length,
      "url": url,
      "highQCoverImage": highQCoverImage,
      "startMs": startMs,
      "durationMs": durationMs,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      "identifier": identifier,
      "title": title,
      "name": name,
      "track": track,
      "size": size,
      "length": length,
      "url": url,
      "highQCoverImage": highQCoverImage,
      "startMs": startMs,
      "durationMs": durationMs,
    };
  }
}
