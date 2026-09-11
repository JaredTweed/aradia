import 'dart:async';
import 'package:aradia/widgets/low_and_high_image.dart';

import 'package:aradia/resources/designs/app_colors.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/utils/book_navigation.dart';
import 'package:aradia/resources/services/audio_handler_provider.dart';
import 'package:aradia/resources/services/my_audio_handler.dart';
import 'package:aradia/screens/audiobook_player/widgets/track_section_dialog.dart';
import 'package:aradia/utils/optimized_timer.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:we_slide/we_slide.dart';

import 'widgets/controls.dart';
import 'widgets/equalizer_dialog.dart';
import 'widgets/equalizer_icon.dart';
import 'widgets/progress_bar_widget.dart';
import 'widgets/chromecast_button.dart';

class AudiobookPlayer extends StatefulWidget {
  const AudiobookPlayer({super.key});

  @override
  State<AudiobookPlayer> createState() => _AudiobookPlayerState();
}

class _AudiobookPlayerState extends State<AudiobookPlayer> {
  late AudioHandlerProvider audioHandlerProvider;
  late Box<dynamic> playingAudiobookDetailsBox;

  // variables for timer and skip silence
  late final OptimizedTimer _sleepTimer;
  StreamSubscription<PositionData>? _positionSubscription;
  bool _isEndOfChapterTimerActive = false;

  // ValueNotifier for skip silence to prevent unnecessary rebuilds
  final ValueNotifier<bool> _skipSilenceNotifier = ValueNotifier<bool>(false);

  // GlobalKey for equalizer icon to refresh it
  final GlobalKey<EqualizerIconState> _equalizerIconKey =
      GlobalKey<EqualizerIconState>();

  @override
  void initState() {
    super.initState();
    playingAudiobookDetailsBox = Hive.box('playing_audiobook_details_box');
    _sleepTimer = OptimizedTimer();
  }

  @override
  void dispose() {
    _sleepTimer.dispose();
    _skipSilenceNotifier.dispose();
    _positionSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    audioHandlerProvider = Provider.of<AudioHandlerProvider>(context);
    // Initialize skip silence state
    _skipSilenceNotifier.value = audioHandlerProvider.audioHandler.skipSilence;
  }

  Future<void> startTimer(Duration duration) async {
    _sleepTimer.cancel();
    _isEndOfChapterTimerActive = false;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    if (!mounted) return;
    if (duration == TimerDurations.endOfChapter) {
      _startEndOfChapterTimer();
      return;
    }
    _sleepTimer.start(duration: duration, onExpired: _onTimerExpired);
  }

  void _onTimerExpired() {
    _isEndOfChapterTimerActive = false;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    audioHandlerProvider.audioHandler.pause();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Sleep timer finished. Audiobook paused.')),
      );
    }
  }

  void _startEndOfChapterTimer() {
    final handler = audioHandlerProvider.audioHandler;
    final targetIndex = handler.playbackState.value.queueIndex;
    _isEndOfChapterTimerActive = true;
    _positionSubscription = handler.getPositionStream().listen((data) {
      if (!_isEndOfChapterTimerActive) return;
      // Catch automatic chapter transitions as well as reaching the final chapter's end.
      if (handler.playbackState.value.queueIndex != targetIndex ||
          (data.duration > Duration.zero && data.position >= data.duration)) {
        _sleepTimer.cancel();
        _onTimerExpired();
        return;
      }
      if (!handler.playbackState.value.playing ||
          handler.playbackState.value.processingState !=
              AudioProcessingState.ready ||
          data.duration <= Duration.zero) {
        _sleepTimer.cancel();
        return;
      }
      final remaining = data.duration - data.position;
      _sleepTimer.start(
        duration: Duration(
            microseconds: (remaining.inMicroseconds / handler.speed).ceil()),
        onExpired: () {
          if (handler.playbackState.value.playing &&
              handler.playbackState.value.processingState ==
                  AudioProcessingState.ready &&
              data.duration - handler.position <=
                  const Duration(milliseconds: 200)) {
            _onTimerExpired();
          }
        },
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Timer set to pause at the end of this chapter.')),
    );
  }

  void cancelTimer() {
    _sleepTimer.cancel();
    _isEndOfChapterTimerActive = false;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sleep timer canceled.')),
    );
  }

  void showTimerOptions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardColor : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Set a Sleep Timer",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 15),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                _timerButton(context, "15 min", TimerDurations.fifteenMinutes),
                _timerButton(context, "30 min", TimerDurations.thirtyMinutes),
                _timerButton(
                    context, "45 min", TimerDurations.fortyFiveMinutes),
                _timerButton(context, "60 min", TimerDurations.oneHour),
                _timerButton(context, "90 min", TimerDurations.ninetyMinutes),
                _endOfChapterTimerButton(context),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  ElevatedButton _timerButton(
      BuildContext context, String label, Duration duration) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
        foregroundColor: isDark ? Colors.white : Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
      ),
      onPressed: () {
        startTimer(duration);
        Navigator.pop(context);
      },
      child: Text(label),
    );
  }

  ElevatedButton _endOfChapterTimerButton(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryColor.withValues(alpha: 0.8),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
      ),
      onPressed: () async {
        await startTimer(TimerDurations.endOfChapter);
        if (context.mounted) Navigator.pop(context);
      },
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.skip_next, size: 16),
          SizedBox(width: 4),
          Text('End of Chapter'),
        ],
      ),
    );
  }

  // -------- Artwork helpers (handle local file:// and remote http/https) -----

  Widget _artLarge(Uri? art, {double size = 250}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: LowAndHighImage(
          lowQImage: art?.toString() ?? '',
          highQImage: null,
          height: size,
          width: size),
    );
  }

  void _showTrackSelectionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => TrackSelectionDialog(
        audioHandler: audioHandlerProvider.audioHandler,
      ),
    );
  }

  void _showEqualizerDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => EqualizerDialog(
        audioHandler: audioHandlerProvider.audioHandler,
      ),
    );
    // Refresh the equalizer icon after dialog closes
    _equalizerIconKey.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: audioHandlerProvider.audioHandler.mediaItem,
      builder: (context, snapshot) {
        if (snapshot.data == null) {
          return const SizedBox.shrink();
        }
        final MediaItem mediaItem = snapshot.data!;

        // Decide what to show for title/subtitle when there's only one track.
        // We read the same Hive box you already use to persist "now playing".
        final box = playingAudiobookDetailsBox;
        final filesDyn = box.get('audiobookFiles') as List?;
        final isSingleTrack = (filesDyn?.length ?? 0) <= 1;

        // Titles to render in the app bar and in the large title below the cover.
        final headerTitle = isSingleTrack
            ? (mediaItem.album ?? mediaItem.title)
            : mediaItem.title;
        final contentTitle = headerTitle; // keep the big center title in sync

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            automaticallyImplyLeading: false,
            leading: IconButton(
              tooltip: 'Collapse player',
              icon: const Icon(Icons.expand_more),
              onPressed: () => context.read<WeSlideController>().hide(),
            ),
            actions: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    tooltip: 'Book details and downloads',
                    icon: const Icon(Icons.more_horiz),
                    onPressed: () {
                      final saved = box.get('audiobook');
                      if (saved is! Map) return;
                      final files = (box.get('audiobookFiles') as List? ?? [])
                          .map((value) => AudiobookFile.fromMap(value as Map))
                          .toList();
                      openBookDetails(context, Audiobook.fromMap(saved), files);
                    },
                  ),
                  ChromeCastButton(
                    chromeCastService:
                        audioHandlerProvider.audioHandler.chromeCastService,
                  ),
                  IconButton(
                    tooltip: 'Equalizer',
                    onPressed: () {
                      _showEqualizerDialog(context);
                    },
                    icon: EqualizerIcon(
                      key: _equalizerIconKey,
                      size: 25,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Chapters',
                    onPressed: () {
                      _showTrackSelectionDialog(context);
                    },
                    icon: Icon(Icons.list, size: 30),
                  ),
                ],
              ),
            ],
          ),
          body: Container(
            width: double.infinity,
            height: double.infinity,
            color: Theme.of(context).scaffoldBackgroundColor,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  0,
                  20,
                  20 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 30),

                    // Modern cover art with glassmorphism effect
                    Hero(
                      tag: 'audiobook_cover',
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 12,
                                offset: const Offset(0, 4))
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: _artLarge(mediaItem.artUri,
                              size: (MediaQuery.sizeOf(context).width - 64)
                                  .clamp(160.0, 280.0)),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Modern title section with better typography
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          Text(
                            contentTitle,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? AppColors.darkTextColor
                                  : AppColors.textColor,
                              height: 1.2,
                            ),
                            textAlign: TextAlign.center,
                            softWrap: true,
                          ),
                          if (!isSingleTrack) ...[
                            const SizedBox(height: 8),
                            Text(
                              mediaItem.album ?? 'Unknown',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? AppColors.listTileSubtitleColor
                                    : AppColors.subtitleTextColorLight,
                                height: 1.3,
                              ),
                              softWrap: true,
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            mediaItem.artist ?? 'Unknown',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? AppColors.listTileSubtitleColor
                                      .withValues(alpha: 0.8)
                                  : AppColors.subtitleTextColorLight,
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                            softWrap: true,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Modern progress bar container
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: ProgressBarWidget(
                        audioHandler: audioHandlerProvider.audioHandler,
                      ),
                    ),

                    const SizedBox(height: 40),
                    // Modern controls container with glassmorphism
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.white.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 12,
                              offset: const Offset(0, 4))
                        ],
                      ),
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _sleepTimer.isActive,
                        builder: (context, isTimerActive, child) {
                          return ValueListenableBuilder<Duration?>(
                            valueListenable: _sleepTimer.remainingTime,
                            builder: (context, activeTimerDuration, child) {
                              return ValueListenableBuilder<bool>(
                                valueListenable: _skipSilenceNotifier,
                                builder: (context, skipSilence, child) {
                                  return Controls(
                                    audioHandler:
                                        audioHandlerProvider.audioHandler,
                                    onTimerPressed: showTimerOptions,
                                    isTimerActive: isTimerActive,
                                    activeTimerDuration: activeTimerDuration,
                                    onCancelTimer: cancelTimer,
                                    onToggleSkipSilence: () {
                                      final newValue =
                                          !_skipSilenceNotifier.value;
                                      _skipSilenceNotifier.value = newValue;
                                      audioHandlerProvider.audioHandler
                                          .setSkipSilence(newValue);
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          duration: const Duration(seconds: 1),
                                          content: Text(
                                            newValue
                                                ? 'Skip Silence Enabled'
                                                : 'Skip Silence Disabled',
                                          ),
                                        ),
                                      );
                                    },
                                    skipSilence: skipSilence,
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
