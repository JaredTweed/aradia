// lib/resources/services/my_audio_handler.dart
import 'dart:async';
import 'dart:io';

import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/archive_api.dart';
import 'package:aradia/resources/models/local_audiobook.dart';
import 'package:aradia/utils/media_helper.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/resources/models/history_of_audiobook.dart';
import 'package:aradia/resources/services/local/cover_image_service.dart';
import 'package:aradia/resources/services/chromecast_service.dart';
import 'package:aradia/utils/app_logger.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

// Turn a local path or remote URL into a proper Uri for MediaItem.artUri.
Uri? _artUriFrom(String? s) {
  if (s == null || s.isEmpty) return null;
  final local = asLocalPath(s);
  return local != null ? Uri.file(local) : Uri.parse(s);
}

class MyAudioHandler extends BaseAudioHandler {
  // Audio effects
  final AndroidEqualizer _equalizer = AndroidEqualizer();
  final AndroidLoudnessEnhancer _loudnessEnhancer = AndroidLoudnessEnhancer();

  // ChromeCast service
  final ChromeCastService _chromeCastService = ChromeCastService();
  ChromeCastService get chromeCastService => _chromeCastService;

  late final AudioPlayer _player;

  List<AudioSource>? _audioSources;
  List<AudioSource>? get audioSources => _audioSources;

  Box<dynamic> playingAudiobookDetailsBox =
      Hive.box('playing_audiobook_details_box');

  final HistoryOfAudiobook historyOfAudiobook = HistoryOfAudiobook();
  Timer? _positionUpdateTimer;

  bool _sessionConfigured = false;
  bool _isReinitializing = false;
  Future<void> _pendingInitialization = Future.value();

  MyAudioHandler() {
    _player = AudioPlayer(
      audioPipeline: AudioPipeline(
        androidAudioEffects: [_equalizer, _loudnessEnhancer],
      ),
    );
  }

  StreamSubscription<String>? _coverSub;

  // Write barrier + context about the current audiobook
  bool _canPersistProgress = false;
  String? _activeAudiobookId;

  // Debounce MRU/position writes so UIs don’t “flap”
  DateTime _lastPersistAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _persistInterval = Duration(seconds: 12);

  // Subscriptions to keep PlaybackState in sync
  StreamSubscription<PlaybackEvent>? _eventSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<int?>? _indexSub;
  StreamSubscription<Duration?>? _durationSub;

  Future<void> _persistInstant() async {
    if (!_canPersistProgress || _isReinitializing) return;
    final id = _activeAudiobookId;
    final idx = _player.currentIndex;
    if (id == null || idx == null) return;
    final liveMs = _player.position.inMilliseconds;
    await historyOfAudiobook.updateAudiobookPosition(id, idx, liveMs);
    await playingAudiobookDetailsBox.putAll({'index': idx, 'position': liveMs});
    _lastPersistAt = DateTime.now();
  }

  /// Rebuild the queue from Hive on cold start *without* starting playback.
  Future<void> restoreIfNeeded() async {
    await _restoreQueueFromBoxIfEmpty(); // already silent (no play)
    // Initialize ChromeCast
    // await _chromeCastService.initialize();
    // Make sure the UI gets an immediate state + current media item
    _broadcastState(_player.playbackEvent);
  }

  Future<void> _ensureAudioSession() async {
    if (_sessionConfigured) return;

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    if (Platform.isAndroid) {
      await _player.setAndroidAudioAttributes(
        const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
      );
    }

    // Pause if headphones unplugged
    session.becomingNoisyEventStream.listen((_) {
      if (_player.playing) pause();
    });

    _sessionConfigured = true;

    // Keep notification/media session state in lock-step with the real player
    _bindStatePipelines();
  }

  void _bindStatePipelines() {
    _eventSub?.cancel();
    _playerStateSub?.cancel();
    _playingSub?.cancel();
    _coverSub?.cancel(); // ← add

    _eventSub = _player.playbackEventStream.listen(_broadcastState);
    _playerStateSub = _player.playerStateStream.listen((_) {
      _broadcastState(_player.playbackEvent);
    });
    _playingSub = _player.playingStream.listen((_) {
      _broadcastState(_player.playbackEvent);
    });
    _durationSub?.cancel();
    _durationSub = _player.durationStream.listen((duration) {
      if (_isReinitializing || duration == null || duration <= Duration.zero) {
        return;
      }
      final index = _player.currentIndex;
      if (index == null || index >= queue.value.length) return;
      final items = [...queue.value];
      if (items[index].duration == duration) return;
      items[index] = items[index].copyWith(duration: duration);
      queue.add(items);
      mediaItem.add(items[index]);
    });

    // swap art immediately if the active audiobook’s cover mapping changes
    _coverSub = coverArtBus.stream.listen((key) {
      if (key.isEmpty) return;
      if (_activeAudiobookId == null) return;
      if (key == _activeAudiobookId) {
        _refreshActiveCoverArt();
      }
    });
  }

  Future<Uri?> _resolveActiveArtUri() async {
    final id = _activeAudiobookId;
    if (id == null) return null;

    // Prefer mapped cover (custom)
    final mapped = await getMappedCoverImage(id);
    final byMap = _artUriFrom(mapped);
    if (byMap != null) return byMap;

    // Fallback: whatever is in the "now playing" audiobook (Hive)
    try {
      final map = Map<String, dynamic>.from(
        playingAudiobookDetailsBox.get('audiobook') ?? {},
      );
      final v = map['lowQCoverImage'] as String?;
      final byBox = _artUriFrom(v);
      if (byBox != null) return byBox;
    } catch (_) {}

    // Last resort: keep existing item art
    return mediaItem.value?.artUri;
  }

  Future<void> _refreshActiveCoverArt() async {
    final id = _activeAudiobookId;
    if (id == null) return;
    if (_audioSources == null || queue.value.isEmpty) return;

    final newUri = await _resolveActiveArtUri();
    if (newUri == null) return;

    final old = queue.value;
    final rebuilt = <MediaItem>[];
    for (final item in old) {
      rebuilt.add(MediaItem(
        id: item.id,
        album: item.album,
        title: item.title,
        artist: item.artist,
        artUri: newUri,
        extras: item.extras,
        duration: item.duration,
        genre: item.genre,
        playable: item.playable,
        displayTitle: item.displayTitle,
        displaySubtitle: item.displaySubtitle,
        displayDescription: item.displayDescription,
        rating: item.rating,
      ));
    }

    queue.add(rebuilt);

    final idx = _player.currentIndex ?? 0;
    if (idx >= 0 && idx < rebuilt.length) {
      mediaItem.add(rebuilt[idx]);
    }

    // Keep Hive "audiobook.lowQCoverImage" as-is; selector already updates it.
  }

  Future<void> refreshBookMetadata(LocalAudiobook book) async {
    if (_activeAudiobookId != MediaHelper.bookKeyForLocal(book)) return;
    final artPath = await resolveCoverForLocal(book);
    final rebuilt = queue.value
        .map((item) => item.copyWith(
              album: book.title,
              artist: book.author,
              artUri: _artUriFrom(artPath),
            ))
        .toList();
    queue.add(rebuilt);
    final index = _player.currentIndex;
    if (index != null && index < rebuilt.length) mediaItem.add(rebuilt[index]);
    final saved = playingAudiobookDetailsBox.get('audiobook');
    if (saved is Map) {
      await playingAudiobookDetailsBox.put('audiobook',
          Map<String, dynamic>.from(saved)..['lowQCoverImage'] = artPath ?? '');
    }
  }

  Future<void> initSongs(List<AudiobookFile> files, Audiobook audiobook,
      int initialIndex, int positionInMilliseconds) {
    final operation = _pendingInitialization.then((_) => _initializeSongs(
        files, audiobook, initialIndex, positionInMilliseconds));
    _pendingInitialization = operation.catchError((Object error) {
      AppLogger.error('Unable to initialize audiobook: $error');
    });
    return operation;
  }

  Future<void> _initializeSongs(
    List<AudiobookFile> files,
    Audiobook audiobook,
    int initialIndex,
    int positionInMilliseconds,
  ) async {
    if (audiobook.origin == 'download' && files.isNotEmpty) {
      final current = files[initialIndex.clamp(0, files.length - 1)];
      final local = asLocalPath(current.url);
      if (local == null || !await File(local).exists()) {
        final remote = await ArchiveApi().getAudiobookFiles(audiobook.id);
        files = remote.fold(
            (error) => throw StateError(
                'This download was removed. Connect to the internet to stream it.'),
            (value) => value);
        final matching = files.indexWhere(
            (file) => current.title != null && file.title == current.title);
        initialIndex = matching >= 0 ? matching : (current.track ?? 1) - 1;
        audiobook = audiobook.copyWith(origin: 'librivox');
      }
    }
    if (files.isEmpty ||
        files.any((file) => file.url == null || file.url!.isEmpty)) {
      throw ArgumentError('The audiobook has no playable audio files.');
    }
    initialIndex = initialIndex.clamp(0, files.length - 1);
    positionInMilliseconds =
        positionInMilliseconds < 0 ? 0 : positionInMilliseconds;
    await _persistInstant();
    _isReinitializing = true;

    try {
      await _ensureAudioSession();

      // Disable persistence until the new queue is fully settled
      _canPersistProgress = false;
      _activeAudiobookId = audiobook.id;

      await playingAudiobookDetailsBox.putAll({
        'audiobook': audiobook.toMap(),
        'audiobookFiles': files.map((f) => f.toMap()).toList(),
        'index': initialIndex,
        'position': positionInMilliseconds,
      });

      await _player.stop();

      queue.add([]);
      mediaItem.add(null);

      _positionUpdateTimer?.cancel();

      playbackState.add(
        playbackState.value.copyWith(
          controls: const [],
          systemActions: const {},
          processingState: AudioProcessingState.idle,
          playing: false,
          bufferedPosition: Duration.zero,
          speed: 1.0,
          queueIndex: null,
        ),
      );

      // Build MediaItems & Sources
      final mediaItems = <MediaItem>[];
      final sources = <AudioSource>[];

      for (final song in files) {
        // Pick one art string: prefer per-track, else audiobook fallback
        String? artStr = audiobook.origin == "download"
            ? audiobook.lowQCoverImage
            : (song.highQCoverImage ?? audiobook.lowQCoverImage);
        final art = _artUriFrom(artStr);

        final item = MediaItem(
          id: song.track.toString(),
          album: audiobook.title,
          title: song.title ?? '',
          artist: audiobook.author ?? 'Librivox',
          duration: song.duration,
          artUri: art, // ← this can be file://... or https://...
          extras: {
            'url': song.url,
            'audiobook_id': audiobook.id,
            'startMs': song.startMs,
            'durationMs': song.durationMs,
          },
        );
        mediaItems.add(item);

        if (song.url != null) {
          final uri = song.url!.startsWith('/')
              ? Uri.file(song.url!)
              : Uri.parse(song.url!);

          // If this "file" is actually a chapter slice, clip it
          if ((song.startMs ?? 0) > 0 || (song.durationMs ?? 0) > 0) {
            final start = Duration(milliseconds: song.startMs ?? 0);
            final end = (song.durationMs != null)
                ? start + Duration(milliseconds: song.durationMs!)
                : null; // last chapter to EOF
            sources.add(
              ClippingAudioSource(
                start: start,
                end: end,
                child: AudioSource.uri(uri, tag: item),
              ),
            );
          } else {
            sources.add(AudioSource.uri(uri, tag: item));
          }
        }
      }

      final safeIndex =
          sources.isEmpty ? 0 : initialIndex.clamp(0, sources.length - 1);

      addQueueItems(mediaItems);
      if (mediaItems.isNotEmpty) {
        mediaItem.add(mediaItems[safeIndex]);
      }

      _audioSources = sources;

      await _player.setAudioSources(
        _audioSources!,
        initialIndex: safeIndex,
        initialPosition: Duration(milliseconds: positionInMilliseconds),
      );

      _listenForCurrentSongIndexChanges();
      if (_player.duration != null && mediaItems.isNotEmpty) {
        final items = [...queue.value];
        items[safeIndex] =
            items[safeIndex].copyWith(duration: _player.duration);
        queue.add(items);
        mediaItem.add(items[safeIndex]);
      }

      // Only add to history once, after we have a settled start
      await historyOfAudiobook.addToHistory(
        audiobook,
        files,
        safeIndex,
        positionInMilliseconds,
      );

      _startPositionUpdateTimer(audiobook.id);

      _canPersistProgress = true; // lift the barrier
      _lastPersistAt = DateTime.now().subtract(_persistInterval);

      // If ChromeCast is connected, load the audiobook to ChromeCast
      if (_chromeCastService.isConnected) {
        try {
          // Pause local player to avoid double playback
          await _player.pause();

          await _chromeCastService.loadAudiobook(
            audiobook,
            files,
            safeIndex,
            Duration(milliseconds: positionInMilliseconds),
          );
          AppLogger.debug('Audiobook loaded to ChromeCast');
        } catch (e) {
          AppLogger.error('Failed to load audiobook to ChromeCast: $e');
        }
      }

      // Broadcast once after init settles (ensures controls show immediately)
      _broadcastState(_player.playbackEvent);
    } finally {
      _isReinitializing = false;
    }
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    queue.add([...queue.value, ...mediaItems]);
  }

  void _listenForCurrentSongIndexChanges() {
    _indexSub?.cancel();
    _indexSub = _player.currentIndexStream.listen((index) {
      if (_isReinitializing) return;
      if (index == null) return;

      final playList = queue.value;
      if (index >= playList.length) return;

      final item = playList[index];
      mediaItem.add(item);
      playingAudiobookDetailsBox.put('index', index);

      // Don’t persist anything until barrier is lifted
      if (!_canPersistProgress) return;

      final audiobookId = item.extras?['audiobook_id'] as String?;
      if (audiobookId == null || audiobookId != _activeAudiobookId) return;
      if (!_player.playing) return; // don’t push MRU while not playing

      _persistNow(audiobookId, index);
    });
  }

  void _persistNow(String audiobookId, int index) {
    final now = DateTime.now();
    if (now.difference(_lastPersistAt) < _persistInterval) return;

    final liveMs = _player.position.inMilliseconds;
    if (liveMs >= 0) {
      historyOfAudiobook.updateAudiobookPosition(audiobookId, index, liveMs);
      playingAudiobookDetailsBox.putAll({'index': index, 'position': liveMs});
      _lastPersistAt = now;
      AppLogger.debug('Position updated: $liveMs ms');
    }
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    final processing = _player.processingState;
    final audioProcessing = const {
      ProcessingState.idle: AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    }[processing]!;

    // Controls shown in quick settings / notification
    final controls = <MediaControl>[
      const MediaControl(
          androidIcon: 'drawable/ic_replay_10',
          label: 'Back 10 seconds',
          action: MediaAction.rewind),
      if (playing) MediaControl.pause else MediaControl.play,
      const MediaControl(
          androidIcon: 'drawable/ic_forward_30',
          label: 'Forward 30 seconds',
          action: MediaAction.fastForward),
      if (_player.hasNext)
        MediaControl.custom(
            androidIcon: 'drawable/audio_service_skip_next',
            label: 'Next chapter',
            name: 'nextChapter'),
    ];

    playbackState.add(
      playbackState.value.copyWith(
        controls: controls,
        androidCompactActionIndices: const [0, 1, 2],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setSpeed,
        },
        processingState: audioProcessing,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: event.currentIndex,
      ),
    );
  }

  void _startPositionUpdateTimer(String audiobookId) {
    _positionUpdateTimer?.cancel();
    _positionUpdateTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_isReinitializing || !_canPersistProgress) return;
      if (audiobookId != _activeAudiobookId) return;
      if (!_player.playing) return;

      final currentIndex = _player.currentIndex;
      if (currentIndex != null) {
        _persistNow(audiobookId, currentIndex);
      }
    });
  }

  Stream<PositionData> getPositionStream() {
    return Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
      _player.positionStream,
      _player.bufferedPositionStream,
      _player.durationStream,
      (position, bufferedPosition, duration) {
        return PositionData(
          position,
          bufferedPosition,
          duration ?? Duration.zero,
        );
      },
    );
  }

  // Cold-restore only: rebuild queue from Hive if we have nothing loaded.
  Future<void> _restoreQueueFromBoxIfEmpty() async {
    if (_isReinitializing) return;
    if ((_audioSources?.isNotEmpty ?? false)) return;

    try {
      final box = playingAudiobookDetailsBox;
      final storedAudiobookMap = box.get('audiobook');
      final storedFiles = box.get('audiobookFiles');
      if (storedAudiobookMap == null || storedFiles == null) return;

      final audiobook =
          Audiobook.fromMap(Map<String, dynamic>.from(storedAudiobookMap));
      final files = (storedFiles as List)
          .map(
              (e) => AudiobookFile.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();

      final index = (box.get('index') as int?) ?? 0;
      final position = (box.get('position') as int?) ?? 0;

      await initSongs(files, audiobook, index, position);
    } catch (_) {
      // best-effort only
    }
  }

  String? getCurrentAudiobookId() {
    final extras = mediaItem.value?.extras;
    return extras == null ? null : (extras['audiobook_id'] as String?);
  }

  List<AudioSource> getAudioSourcesFromPlaylist() {
    return _audioSources ?? const [];
  }

  // ── AudioHandler overrides ────────────────────────────────────────────────
  /// Remove deleted offline audio from the live queue as well as storage.
  Future<void> downloadedChapterDeleted(String bookId, String path) async {
    final saved = playingAudiobookDetailsBox.get('audiobook');
    if (saved is! Map ||
        saved['id'] != bookId ||
        saved['origin'] != 'download') {
      return;
    }
    final files =
        (playingAudiobookDetailsBox.get('audiobookFiles') as List? ?? [])
            .map((value) => AudiobookFile.fromMap(value as Map))
            .toList();
    if (!files.any((file) => asLocalPath(file.url) == path)) return;
    final index = (_player.currentIndex ?? 0).clamp(0, files.length - 1);
    final current = files[index];
    final position = _player.position.inMilliseconds;
    final wasPlaying = _player.playing;
    final remaining =
        files.where((file) => asLocalPath(file.url) != path).toList();
    await pause();
    if (remaining.isEmpty) {
      await stop();
      return;
    }
    final retainedIndex =
        remaining.indexWhere((file) => file.url == current.url);
    await initSongs(
        remaining,
        Audiobook.fromMap(saved),
        retainedIndex >= 0
            ? retainedIndex
            : index.clamp(0, remaining.length - 1),
        retainedIndex >= 0 ? position : 0);
    if (wasPlaying && retainedIndex >= 0) await play();
  }

  @override
  Future<void> play() async {
    await _pendingInitialization;
    await _restoreQueueFromBoxIfEmpty(); // only at cold start
    final saved = playingAudiobookDetailsBox.get('audiobook');
    final currentPath = asLocalPath(mediaItem.value?.extras?['url'] as String?);
    if (saved is Map &&
        saved['origin'] == 'download' &&
        currentPath != null &&
        !await File(currentPath).exists()) {
      final files =
          (playingAudiobookDetailsBox.get('audiobookFiles') as List? ?? [])
              .map((value) => AudiobookFile.fromMap(value as Map))
              .toList();
      await initSongs(files, Audiobook.fromMap(saved),
          _player.currentIndex ?? 0, _player.position.inMilliseconds);
    }

    // Route to ChromeCast if connected
    if (_chromeCastService.isConnected) {
      await _chromeCastService.play();
    } else {
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero, index: 0);
      }
      final id = _activeAudiobookId;
      if (id != null) _startPositionUpdateTimer(id);
      unawaited(_player.play());
    }

    _broadcastState(_player.playbackEvent);
  }

  @override
  Future<void> pause() async {
    // Route to ChromeCast if connected
    if (_chromeCastService.isConnected) {
      await _chromeCastService.pause();
    } else {
      await _player.pause();
    }

    await _persistInstant();
    _broadcastState(_player.playbackEvent);
  }

  @override
  Future<void> stop() async {
    _positionUpdateTimer?.cancel();

    // Route to ChromeCast if connected
    if (_chromeCastService.isConnected) {
      await _chromeCastService.stop();
    } else {
      await _player.stop();
    }

    _broadcastState(_player.playbackEvent);
    await _persistInstant();
  }

  @override
  Future<void> seek(Duration position) async {
    final duration = mediaItem.value?.duration;
    position = position < Duration.zero ? Duration.zero : position;
    if (duration != null && position > duration) position = duration;
    // Route to ChromeCast if connected
    if (_chromeCastService.isConnected) {
      await _chromeCastService.seek(position);
    } else {
      await _player.seek(position);
    }

    _broadcastState(_player.playbackEvent);
    await _persistInstant();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= queue.value.length) return;
    await _player.seek(Duration.zero, index: index);
    await _persistInstant();
    await play();
  }

  @override
  Future<void> skipToNext() async {
    // Route to ChromeCast if connected
    if (_chromeCastService.isConnected) {
      await _chromeCastService.skipToNext();
    } else {
      await _player.seekToNext();
    }

    _broadcastState(_player.playbackEvent);
    await _persistInstant();
  }

  @override
  Future<dynamic> customAction(String name,
      [Map<String, dynamic>? extras]) async {
    if (name == 'nextChapter') return skipToNext();
    return super.customAction(name, extras);
  }

  @override
  Future<void> skipToPrevious() async {
    // Route to ChromeCast if connected
    if (_chromeCastService.isConnected) {
      await _chromeCastService.skipToPrevious();
    } else {
      await _player.seekToPrevious();
    }

    _broadcastState(_player.playbackEvent);
    await _persistInstant();
  }

  // Map Android's seekForward/seekBackward to fast-forward/rewind
  static const _ffAmount = Duration(seconds: 30);
  static const _rwAmount = Duration(seconds: 10);

  @override
  Future<void> fastForward() async {
    await seek((_chromeCastService.isConnected
            ? _chromeCastService.currentPosition
            : _player.position) +
        _ffAmount);
  }

  @override
  Future<void> rewind() async {
    await seek((_chromeCastService.isConnected
            ? _chromeCastService.currentPosition
            : _player.position) -
        _rwAmount);
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    _broadcastState(_player.playbackEvent);
  }

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
  }

  Future<void> setSkipSilence(bool skipSilence) async {
    await _player.setSkipSilenceEnabled(skipSilence);
  }

  // ── Equalizer controls ────────────────────────────────────────────────────

  /// Set equalizer band level
  /// bandIndex: 0-4 for the 5 frequency bands (60Hz, 230Hz, 910Hz, 4kHz, 14kHz)
  /// gain: -15.0 to +15.0 dB
  Future<void> setEqualizerBand(int bandIndex, double gain) async {
    try {
      final clampedGain = gain.clamp(-15.0, 15.0);
      final parameters = await _equalizer.parameters;
      final bands = parameters.bands;

      if (bandIndex >= 0 && bandIndex < bands.length) {
        await bands[bandIndex].setGain(clampedGain);
      }
    } catch (e) {
      AppLogger.error('Error setting equalizer band: $e');
    }
  }

  /// Enable or disable the equalizer
  Future<void> setEqualizerEnabled(bool enabled) async {
    try {
      if (!Platform.isAndroid) {
        AppLogger.debug('Equalizer not available on this platform');
        return;
      }

      await _equalizer.setEnabled(enabled);
      AppLogger.debug('Equalizer ${enabled ? "enabled" : "disabled"}');
    } catch (e) {
      AppLogger.error('Error setting equalizer enabled: $e');
    }
  }

  /// Set audio balance (left/right channel volume)
  /// balance: -1.0 (left) to +1.0 (right), 0.0 = center
  /// Note: Balance is implemented by adjusting volume per channel
  Future<void> setBalance(double balance) async {
    try {
      await _player.setBalance(balance);
    } catch (e) {
      AppLogger.error('Error setting balance: $e');
    }
  }

  Future<void> setPitch(double pitch) async {
    try {
      await _player.setPitch(pitch);
    } catch (e) {
      AppLogger.error('Error setting pitch: $e');
    }
  }

  /// Set loudness enhancer target gain
  /// targetGain: 0.0 to 1000.0 (millibels)
  Future<void> setLoudnessEnhancer(double targetGain) async {
    try {
      if (!Platform.isAndroid) {
        AppLogger.debug('Loudness enhancer not available on this platform');
        return;
      }

      final clampedGain = targetGain.clamp(0.0, 1000.0);
      await _loudnessEnhancer.setTargetGain(clampedGain);
      AppLogger.debug('Loudness enhancer set to: $clampedGain mB');
    } catch (e) {
      AppLogger.error('Error setting loudness enhancer: $e');
    }
  }

  /// Get current equalizer parameters
  Future<AndroidEqualizerParameters?> getEqualizerParameters() async {
    try {
      if (!Platform.isAndroid) return null;
      return await _equalizer.parameters;
    } catch (e) {
      AppLogger.error('Error getting equalizer parameters: $e');
      return null;
    }
  }

  Duration get position => _player.position;
  bool get skipSilence => _player.skipSilenceEnabled;
  double get volume => _player.volume;
  double get speed => _player.speed;

  void playPrevious() {
    final length = _audioSources?.length ?? 0;
    if (_player.currentIndex != null && _player.currentIndex! > 0) {
      _player.seekToPrevious();
    } else if (length > 0) {
      _player.seek(Duration.zero, index: 0);
    }
  }

  void playNext() {
    final length = _audioSources?.length ?? 0;
    if (_player.currentIndex != null &&
        length > 0 &&
        _player.currentIndex! < length - 1) {
      _player.seekToNext();
    }
  }
}

class PositionData {
  const PositionData(this.position, this.bufferedPosition, this.duration);
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;
}
