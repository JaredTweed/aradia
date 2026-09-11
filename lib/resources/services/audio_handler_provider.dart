import 'package:aradia/resources/services/my_audio_handler.dart';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';

class AudioHandlerProvider extends ChangeNotifier {
  final MyAudioHandler _audioHandler = MyAudioHandler();
  Future<void>? _initialization;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    await AudioService.init(
      builder: () => _audioHandler,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.oseamiya.librivoxaudiobook',
        androidNotificationChannelName: 'Audio playback',
        androidNotificationOngoing: true,
        androidNotificationIcon: 'drawable/ic_launcher_monochrome',
        rewindInterval: Duration(seconds: 10),
        fastForwardInterval: Duration(seconds: 30),
      ),
    );
    await _audioHandler.restoreIfNeeded();
    notifyListeners();
  }

  MyAudioHandler get audioHandler => _audioHandler;
}
