import 'dart:async';

class GoogleCastDiscoveryCriteria {
  static const kDefaultApplicationId = '';
}

class GoogleCastOptionsAndroid {
  const GoogleCastOptionsAndroid({required String appId});
}

class GoogleCastContext {
  GoogleCastContext._();
  static final instance = GoogleCastContext._();
  void setSharedInstanceWithOptions(GoogleCastOptionsAndroid options) {}
}

class GoogleCastDevice {
  const GoogleCastDevice({this.friendlyName = '', this.modelName});
  final String friendlyName;
  final String? modelName;
}

class GoogleCastSession {}
enum GoogleCastConnectState { disconnected, connected }
enum CastMediaStreamType { buffered }

class GoogleCastDiscoveryManager {
  GoogleCastDiscoveryManager._();
  static final instance = GoogleCastDiscoveryManager._();
  Stream<List<GoogleCastDevice>> get devicesStream => const Stream.empty();
  void startDiscovery() {}
  void stopDiscovery() {}
}

class GoogleCastSessionManager {
  GoogleCastSessionManager._();
  static final instance = GoogleCastSessionManager._();
  Stream<GoogleCastSession?> get currentSessionStream => const Stream.empty();
  GoogleCastConnectState get connectionState => GoogleCastConnectState.disconnected;
  Future<void> startSessionWithDevice(GoogleCastDevice device) async {}
  Future<void> endSessionAndStopCasting() async {}
}

class GoogleCastQueueItem {
  const GoogleCastQueueItem({required GoogleCastMediaInformationIOS mediaInformation});
}
class GoogleCastMediaInformationIOS {
  const GoogleCastMediaInformationIOS({required String contentId, required CastMediaStreamType streamType,
      required Uri contentUrl, required String contentType, required GoogleCastGenericMediaMetadata metadata});
}
class GoogleCastGenericMediaMetadata {
  const GoogleCastGenericMediaMetadata({required String title, required String subtitle,
      required List<GoogleCastImage> images});
}
class GoogleCastImage {
  const GoogleCastImage({required Uri url, required int width, required int height});
}
class GoogleCastQueueLoadOptions {
  const GoogleCastQueueLoadOptions({required int startIndex, required Duration playPosition});
}
class GoogleCastMediaSeekOption {
  const GoogleCastMediaSeekOption({required Duration position});
}
class GoggleCastMediaStatus {}

class GoogleCastRemoteMediaClient {
  GoogleCastRemoteMediaClient._();
  static final instance = GoogleCastRemoteMediaClient._();
  Stream<GoggleCastMediaStatus?> get mediaStatusStream => const Stream.empty();
  Duration get playerPosition => Duration.zero;
  Future<void> queueLoadItems(List<GoogleCastQueueItem> items,
      {required GoogleCastQueueLoadOptions options}) async {}
  Future<void> play() async {}
  Future<void> pause() async {}
  Future<void> stop() async {}
  Future<void> seek(GoogleCastMediaSeekOption option) async {}
  Future<void> queueNextItem() async {}
  Future<void> queuePrevItem() async {}
}
