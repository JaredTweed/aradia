import 'dart:async';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:hive_flutter/hive_flutter.dart';

class HistoryOfAudiobook {
  static final HistoryOfAudiobook _instance = HistoryOfAudiobook._internal();
  static bool _initialized = false;

  factory HistoryOfAudiobook() {
    return _instance;
  }

  HistoryOfAudiobook._internal() {
    _initialize();
  }

  late Box<dynamic> historyOfAudiobookBox;
  final _historyStreamController =
      StreamController<List<HistoryOfAudiobookItem>>.broadcast();

  Stream<List<HistoryOfAudiobookItem>> get historyStream =>
      _historyStreamController.stream;

  Future<void> _initialize() async {
    if (!_initialized) {
      historyOfAudiobookBox = await Hive.openBox('history_of_audiobook_box');
      _initialized = true;

      // Emit the current history (even if it's empty) when the box is initialized
      _historyStreamController.add(getHistory());
    }
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await _initialize();
    }
  }

  Future<void> addToHistory(Audiobook audiobook,
      List<AudiobookFile> audiobookFiles, int index, int position) async {
    await _ensureInitialized();
    final item = HistoryOfAudiobookItem(
      audiobook: audiobook,
      audiobookFiles: audiobookFiles,
      index: index,
      position: position,
      lastModified: DateTime.now(),
    );
    await historyOfAudiobookBox.put(audiobook.id, item.toMap());
    _historyStreamController.add(getHistory());
  }

  List<HistoryOfAudiobookItem> getHistory() {
    if (!_initialized) {
      return [];
    }
    return historyOfAudiobookBox.values
        .map((item) => HistoryOfAudiobookItem.fromMap(item))
        .toList()
      ..sort((a, b) =>
          b.lastModified.compareTo(a.lastModified)); // Sort by lastModified
  }

  HistoryOfAudiobookItem getHistoryOfAudiobookItem(String audiobookId) {
    if (!_initialized) {
      throw Exception('HistoryOfAudiobook is not initialized');
    }
    return HistoryOfAudiobookItem.fromMap(
        historyOfAudiobookBox.get(audiobookId));
  }

  bool isAudiobookInHistory(String audiobookId) {
    if (!_initialized) {
      return false;
    }
    return historyOfAudiobookBox.containsKey(audiobookId);
  }

  Future<bool> isHistoryEmpty() async {
    await _ensureInitialized();
    return historyOfAudiobookBox.isEmpty;
  }

  Future<void> updateAudiobookPosition(
      String audiobookId, int index, int position) async {
    await _ensureInitialized();
    if (historyOfAudiobookBox.containsKey(audiobookId)) {
      var historyItem = HistoryOfAudiobookItem.fromMap(
          historyOfAudiobookBox.get(audiobookId));
      historyItem.index = index;
      historyItem.position = position;
      historyItem.lastModified = DateTime.now();
      await historyOfAudiobookBox.put(audiobookId, historyItem.toMap());
      _historyStreamController.add(getHistory());
    }
  }

  void removeAudiobookFromHistory(String audiobookId) async {
    await _ensureInitialized();
    if (historyOfAudiobookBox.containsKey(audiobookId)) {
      await historyOfAudiobookBox.delete(audiobookId);
      _historyStreamController.add(getHistory());
    }
  }

  void clearHistory() async {
    await _ensureInitialized();
    await historyOfAudiobookBox.clear();
    _historyStreamController.add(getHistory()); // Emit an empty list
  }

  void dispose() {
    _historyStreamController.close();
  }
}

class HistoryOfAudiobookItem {
  /// Keep the same chapter when newly downloaded chapters change queue indexes.
  int indexIn(List<AudiobookFile> files) {
    if (index < 0 || index >= audiobookFiles.length) return -1;
    final previous = audiobookFiles[index];
    final exact = files.indexWhere(
        (file) => file.url == previous.url && file.startMs == previous.startMs);
    if (exact >= 0) return exact;
    // Downloading or deleting a chapter changes its URL, not its identity.
    final matches = <int>[
      for (var i = 0; i < files.length; i++)
        if (previous.title != null &&
            files[i].title == previous.title &&
            files[i].startMs == previous.startMs)
          i
    ];
    if (matches.length == 1) return matches.single;
    return matches
            .where((i) =>
                previous.track != null && files[i].track == previous.track)
            .firstOrNull ??
        -1;
  }

  final Audiobook audiobook;
  final List<AudiobookFile> audiobookFiles;
  int index;
  int position;
  DateTime lastModified;

  HistoryOfAudiobookItem({
    required this.audiobook,
    required this.audiobookFiles,
    required this.index,
    required this.position,
    required this.lastModified,
  });

  Map<String, dynamic> toMap() {
    return {
      'audiobook': audiobook.toMap(),
      'audiobookFiles': audiobookFiles.map((file) => file.toMap()).toList(),
      'index': index,
      'position': position,
      'lastModified': lastModified.toIso8601String(),
    };
  }

  factory HistoryOfAudiobookItem.fromMap(Map<dynamic, dynamic> map) {
    return HistoryOfAudiobookItem(
      audiobook: Audiobook.fromMap(Map<String, dynamic>.from(map['audiobook'])),
      audiobookFiles: List<AudiobookFile>.from(map['audiobookFiles'].map(
          (file) => AudiobookFile.fromMap(Map<String, dynamic>.from(file)))),
      index: map['index'],
      position: map['position'],
      lastModified: DateTime.parse(map['lastModified']),
    );
  }
}
