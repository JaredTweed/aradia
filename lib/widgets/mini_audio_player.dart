// lib/widgets/mini_audio_player.dart
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:aradia/resources/designs/app_colors.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/services/audio_handler_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:aradia/screens/audiobook_player/audiobook_player.dart';
import 'package:provider/provider.dart';
import 'package:we_slide/we_slide.dart';

class MiniAudioPlayer extends StatefulWidget {
  final Box<dynamic> playingAudiobookDetailsBox;
  final StatefulNavigationShell navigationShell;
  final BottomNavigationBar bottomNavigationBar;
  final double bottomNavBarSize;
  final bool isKeyboardOpen;

  const MiniAudioPlayer({
    super.key,
    required this.playingAudiobookDetailsBox,
    required this.navigationShell,
    required this.bottomNavigationBar,
    required this.bottomNavBarSize,
    required this.isKeyboardOpen,
  });

  @override
  State<MiniAudioPlayer> createState() => _MiniAudioPlayerState();
}

class _MiniAudioPlayerState extends State<MiniAudioPlayer> {
  late final WeSlideController weSlideController;

  @override
  void initState() {
    super.initState();
    weSlideController = Provider.of<WeSlideController>(context, listen: false);
  }

  Widget _buildSliderIndicator() {
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  // Helper to display cover art safely for local or remote
  Widget _coverImage(MediaItem mediaItem) {
    final art = mediaItem.artUri;
    if (art == null) {
      return Container(
        width: 50,
        height: 50,
        color: Colors.grey[700],
        child: const Icon(Icons.headphones, color: Colors.white70),
      );
    }

    if (art.scheme == 'file') {
      return Image.file(
        File(art.toFilePath()),
        width: 50,
        height: 50,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.headphones),
      );
    }

    return Image.network(
      art.toString(),
      width: 50,
      height: 50,
      fit: BoxFit.cover,
      errorBuilder: (context, _, __) =>
          const Icon(Icons.broken_image, color: Colors.white54),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = widget.isKeyboardOpen;

    if (keyboardOpen && weSlideController.isOpened) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) weSlideController.hide();
      });
    }

    final handler = context.watch<AudioHandlerProvider>().audioHandler;

    final panelMaxSize = MediaQuery.of(context).size.height;
    final footerHeight = keyboardOpen ? 0.0 : widget.bottomNavBarSize;
    final footer =
        keyboardOpen ? const SizedBox.shrink() : widget.bottomNavigationBar;
    final panelMin = keyboardOpen ? 0.0 : (80 + widget.bottomNavBarSize);

    return WeSlide(
      controller: weSlideController,
      panelMinSize: panelMin,
      panelMaxSize: panelMaxSize,
      footerHeight: footerHeight,
      footer: footer,
      body: widget.navigationShell,
      panel: const AudiobookPlayer(),
      panelHeader: Offstage(
        offstage: keyboardOpen,
        child: Container(
          height: 80,
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: Column(
            children: [
              Center(child: _buildSliderIndicator()),
              Expanded(
                child: StreamBuilder<MediaItem?>(
                  stream: handler.mediaItem,
                  builder: (context, snapshot) {
                    final mediaItem = snapshot.data;
                    if (mediaItem == null) return const SizedBox.shrink();

                    // Determine if this is a single-track book based on what we saved in Hive
                    final box = widget.playingAudiobookDetailsBox;
                    final filesDyn = box.get('audiobookFiles') as List?;
                    final isSingleTrack = (filesDyn?.length ?? 0) <= 1;

                    // Resolve author (prefer from our stored Audiobook, fall back to MediaItem.artist)
                    String? author;
                    final audiobookMap = box.get('audiobook');
                    if (audiobookMap != null) {
                      author = Audiobook.fromMap(audiobookMap).author;
                    }
                    final secondaryLine = isSingleTrack
                        ? (author ?? mediaItem.artist ?? '')
                        : mediaItem.title;

                    return Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                              child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: _coverImage(mediaItem),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // First line: keep the book title (album)
                                    Text(
                                      mediaItem.album ?? "",
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                    // Second line: either the track title (multi-track) or the author (single-track)
                                    Text(
                                      secondaryLine,
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )),
                          StreamBuilder<PlaybackState>(
                            stream: handler.playbackState,
                            builder: (context, s) {
                              final st = s.data;
                              final loading = st?.processingState ==
                                      AudioProcessingState.loading ||
                                  st?.processingState ==
                                      AudioProcessingState.buffering;
                              if (loading) {
                                return const SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: Padding(
                                      padding: EdgeInsets.all(12),
                                      child: CircularProgressIndicator(
                                          color: AppColors.primaryColor,
                                          strokeWidth: 2),
                                    ));
                              }
                              final playing = st?.playing ?? false;
                              return IconButton(
                                icon: Icon(
                                  playing ? Icons.pause : Icons.play_arrow,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                                onPressed: () =>
                                    playing ? handler.pause() : handler.play(),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
