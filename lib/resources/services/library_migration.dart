import 'package:hive/hive.dart';

/// Removes saved references to the retired importer while retaining downloaded audio.
Future<void> migrateSavedLibrary() async {
  for (final boxName in [
    'favourite_audiobooks_box',
    'history_of_audiobook_box'
  ]) {
    final box = Hive.box(boxName);
    final obsoleteKeys = box.keys.where((key) {
      final entry = box.get(key);
      final book = boxName == 'history_of_audiobook_box' && entry is Map
          ? entry['audiobook']
          : entry;
      return book is Map && book['origin'] == 'youtube';
    }).toList();
    await box.deleteAll(obsoleteKeys);
  }
  final playingBox = Hive.box('playing_audiobook_details_box');
  final savedBook = playingBox.get('audiobook');
  if (savedBook is Map && savedBook['origin'] == 'youtube') {
    await playingBox.clear();
  }
  final downloads = Hive.box('download_status_box');
  for (final key in downloads.keys.toList()) {
    final status = downloads.get(key);
    if (key.toString().startsWith('status_') &&
        status is Map &&
        status['isDownloading'] == true) {
      await downloads.put(
          key,
          Map<String, dynamic>.from(status)
            ..['isDownloading'] = false
            ..['error'] = 'Download interrupted. Please retry.');
    }
  }
}
