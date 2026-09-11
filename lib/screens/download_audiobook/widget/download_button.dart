import 'dart:async';
import 'package:aradia/resources/archive_api.dart';
import 'package:aradia/resources/services/audio_handler_provider.dart';
import 'package:provider/provider.dart';
import 'package:hive/hive.dart';
import 'dart:convert';
import 'dart:io';

import 'package:aradia/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ionicons/ionicons.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/resources/services/download/download_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:aradia/utils/permission_helper.dart';
import 'package:aradia/resources/services/download/chapter_downloads.dart';

class DownloadButton extends StatefulWidget {
  final Audiobook audiobook;
  final List<AudiobookFile> audiobookFiles;
  final VoidCallback? onChanged;

  const DownloadButton({
    super.key,
    required this.audiobook,
    required this.audiobookFiles,
    this.onChanged,
  });

  @override
  State<DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<DownloadButton> {
  final DownloadManager _downloadManager = DownloadManager();
  double _progress = 0;
  bool _isDownloading = false;
  bool _isDownloaded = false;
  bool _isManaging = false;
  StreamSubscription<BoxEvent>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    _loadInitialState();
    _statusSubscription = Hive.box('download_status_box')
        .watch(key: 'status_${widget.audiobook.id}')
        .listen((_) {
      if (mounted) setState(_loadInitialState);
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  void _loadInitialState() {
    _progress = _downloadManager.getProgress(widget.audiobook.id);
    _isDownloading = _downloadManager.isDownloading(widget.audiobook.id);
    _isDownloaded = _downloadManager.isDownloaded(widget.audiobook.id);
  }

  Future<void> _handleNotificationPermission(BuildContext context) async {
    if (_isManaging) return;
    _isManaging = true;
    try {
      await _chooseChapters();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      _isManaging = false;
    }
  }

  Future<void> _chooseChapters() async {
    if (_isDownloading || widget.audiobookFiles.isEmpty) return;
    final audioHandler = context.read<AudioHandlerProvider>().audioHandler;
    final base = await getExternalStorageDirectory();
    if (base == null) throw StateError('Download storage is unavailable.');
    final directory =
        Directory('${base.path}/downloads/${widget.audiobook.id}');
    final saved = await ChapterDownloads.completed(directory);
    final urls = saved.map((e) => e['url']).toSet();
    var entries = [
      for (var i = 0; i < widget.audiobookFiles.length; i++)
        ChapterDownloads.entry(widget.audiobookFiles[i], i)
    ];
    final catalogue = File('${directory.path}/catalogue.json');
    if (widget.audiobook.origin == 'download') {
      if (await catalogue.exists()) {
        entries = (jsonDecode(await catalogue.readAsString()) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else {
        final result =
            await ArchiveApi().getAudiobookFiles(widget.audiobook.id);
        entries = result.fold(
            (_) => saved,
            (files) => [
                  for (var i = 0; i < files.length; i++)
                    ChapterDownloads.entry(files[i], i)
                ]);
      }
    }
    final fullCatalogue = entries.isNotEmpty &&
        (widget.audiobook.origin != 'download' ||
            await catalogue.exists() ||
            entries.length > saved.length ||
            !identical(entries, saved));
    if (fullCatalogue) {
      await directory.create(recursive: true);
      await catalogue.writeAsString(jsonEncode(entries));
    }
    // Recognize completed downloads made before the chapter manifest existed.
    if (_isDownloaded && saved.isEmpty) {
      for (final entry in entries) {
        if (await File('${directory.path}/${entry['filename']}').exists()) {
          await ChapterDownloads.record(directory, entry);
          urls.add(entry['url']);
        }
      }
    }
    final selected = <int>{
      for (var i = 0; i < entries.length; i++)
        if (!urls.contains(entries[i]['url'])) i
    };
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                  title: const Text('Manage chapters'),
                  content: SizedBox(
                      width: 480,
                      height: MediaQuery.sizeOf(context).height * 0.5,
                      child: Column(children: [
                        Text(fullCatalogue
                            ? '${urls.length} of ${entries.length} chapters downloaded'
                            : '${urls.length} downloaded chapters • Connect to load the full list'),
                        const SizedBox(height: 8),
                        const Text(
                            'Select missing chapters to download. Use the delete button to remove a chapter from this device.'),
                        Row(children: [
                          TextButton(
                              onPressed: () => update(() {
                                    selected.addAll([
                                      for (var i = 0; i < entries.length; i++)
                                        if (!urls.contains(entries[i]['url'])) i
                                    ]);
                                  }),
                              child: const Text('Select missing')),
                          TextButton(
                              onPressed: () => update(selected.clear),
                              child: const Text('Clear')),
                        ]),
                        Expanded(
                            child: ListView.builder(
                                itemCount: entries.length,
                                itemBuilder: (context, i) {
                                  final downloaded =
                                      urls.contains(entries[i]['url']);
                                  return ListTile(
                                      leading: downloaded
                                          ? const Icon(Icons.offline_pin)
                                          : Checkbox(
                                              value: selected.contains(i),
                                              onChanged: (value) => update(() {
                                                    if (value == true) {
                                                      selected.add(i);
                                                    } else {
                                                      selected.remove(i);
                                                    }
                                                  })),
                                      title: Text(
                                          '${(entries[i]['order'] as int) + 1}. ${entries[i]['title'] ?? 'Chapter'}'),
                                      subtitle: Text(downloaded
                                          ? 'Available offline'
                                          : 'Not downloaded'),
                                      trailing: downloaded
                                          ? IconButton(
                                              tooltip:
                                                  'Delete downloaded chapter',
                                              icon: const Icon(
                                                  Icons.delete_outline),
                                              onPressed: () async {
                                                final remove =
                                                    await showDialog<bool>(
                                                        context: context,
                                                        builder:
                                                            (context) =>
                                                                AlertDialog(
                                                                  title: const Text(
                                                                      'Delete downloaded chapter?'),
                                                                  content: Text(
                                                                      '${entries[i]['title']}\n\nYou can download it again later.'),
                                                                  actions: [
                                                                    TextButton(
                                                                        onPressed: () => Navigator.pop(
                                                                            context,
                                                                            false),
                                                                        child: const Text(
                                                                            'Keep')),
                                                                    TextButton(
                                                                        onPressed: () => Navigator.pop(
                                                                            context,
                                                                            true),
                                                                        child: const Text(
                                                                            'Delete'))
                                                                  ],
                                                                ));
                                                if (remove != true) return;
                                                try {
                                                  await ChapterDownloads.delete(
                                                      directory,
                                                      entries[i]['url']
                                                          as String);
                                                  try {
                                                    await audioHandler
                                                        .downloadedChapterDeleted(
                                                            widget.audiobook.id,
                                                            '${directory.path}/${entries[i]['filename']}');
                                                  } catch (e) {
                                                    AppLogger.debug(
                                                        'Could not refresh playback after chapter deletion: $e');
                                                  }
                                                  urls.remove(
                                                      entries[i]['url']);
                                                  final key =
                                                      'status_${widget.audiobook.id}';
                                                  final status = Map<String,
                                                          dynamic>.from(
                                                      _downloadManager
                                                              .downloadStatusBox
                                                              .get(key) ??
                                                          {});
                                                  if (urls.isEmpty) {
                                                    await _downloadManager
                                                        .downloadStatusBox
                                                        .delete(key);
                                                  } else {
                                                    status.addAll({
                                                      'downloadedCount':
                                                          urls.length,
                                                      'isCompleted': true,
                                                      'isDownloading': false,
                                                      'progress': 1.0
                                                    });
                                                    status.remove('error');
                                                    await _downloadManager
                                                        .downloadStatusBox
                                                        .put(key, status);
                                                  }
                                                  if (context.mounted) {
                                                    update(() {});
                                                  }
                                                } catch (e) {
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(SnackBar(
                                                            content: Text(
                                                                'Could not delete chapter: $e')));
                                                  }
                                                }
                                              },
                                            )
                                          : null);
                                })),
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Done')),
                    FilledButton(
                        onPressed: selected.isEmpty
                            ? null
                            : () => Navigator.pop(context, true),
                        child: Text(urls.length == entries.length
                            ? 'All downloaded'
                            : selected.isEmpty
                                ? 'Select chapters'
                                : 'Download ${selected.length}')),
                  ],
                )));
    if (confirmed == true && mounted) {
      await _startDownload(
          [for (final index in selected.toList()..sort()) entries[index]]);
    }
    if (mounted) widget.onChanged?.call();
  }

  Future<void> _startDownload(List<Map<String, dynamic>> files) async {
    if (!mounted || _isDownloading || widget.audiobookFiles.isEmpty) return;
    await PermissionHelper.handleDownloadPermissionWithDialog(context);
    if (!mounted) return;

    setState(() {
      _isDownloading = true;
    });

    try {
      // we will save audiobook and files in the
      final appDir = await getExternalStorageDirectory();
      if (appDir == null) throw StateError('Download storage is unavailable.');

      // Create parent downloads directory if it doesn't exist
      final downloadsDir = Directory('${appDir.path}/downloads');
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      final downloadDir =
          Directory('${appDir.path}/downloads/${widget.audiobook.id}');
      if (!await downloadDir.exists()) {
        await downloadDir.create();
      }
      // Now create a file name audiobook.txt and save the audiobook details
      final audiobookFile = File('${downloadDir.path}/audiobook.txt');
      // Create a modified copy of the audiobook with origin set to 'download'
      final modifiedAudiobook =
          Map<String, dynamic>.from(widget.audiobook.toMap())
            ..['origin'] = 'download';
      await audiobookFile.writeAsString(jsonEncode(modifiedAudiobook));

      // Now create a file name files.txt and save the audiobook files
      final filesFile = File('${downloadDir.path}/files.txt');
      await filesFile.writeAsString(
        jsonEncode(files),
      );

      await _downloadManager.downloadAudiobook(
        widget.audiobook.id,
        widget.audiobook.title,
        files,
        (progress) {
          if (mounted) {
            setState(() => _progress = progress);
          }
        },
        (completed) {
          if (!mounted) return;

          setState(() {
            _isDownloading = false;
            _isDownloaded = completed;
          });

          if (!completed) {
            final error = _downloadManager.getError(widget.audiobook.id);
            if (error != null) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(error)));
            }
          }
          if (completed) {
            widget.onChanged?.call();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    '${files.length} chapters available offline: ${widget.audiobook.title}'),
              ),
            );
          }
        },
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isDownloading = false;
      });

      AppLogger.debug(e.toString());

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDownloaded) {
      return IconButton(
        tooltip: 'Manage chapter downloads',
        onPressed: () => _handleNotificationPermission(context),
        icon: const Icon(
          Ionicons.cloud_done,
          size: 50,
          color: Colors.white,
        ),
      );
    } else if (_isDownloading) {
      return GestureDetector(
        onTap: () => context.push('/download'),
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 50,
              height: 50,
              child: CircularProgressIndicator(
                value: _progress,
                color: Colors.white,
                strokeWidth: 3,
              ),
            ),
            Text(
              '${(_progress * 100).toInt()}%',
              style: GoogleFonts.ubuntu(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return IconButton(
      tooltip: 'Download chapters',
      onPressed: () => _handleNotificationPermission(context),
      icon: const Icon(
        Ionicons.cloud_download,
        size: 50,
        color: Colors.white,
      ),
    );
  }
}
