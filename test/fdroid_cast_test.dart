import 'package:aradia/config/build_features.dart';
import 'package:aradia/resources/services/chromecast_service.dart';
import 'package:aradia/screens/audiobook_player/widgets/chromecast_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('F-Droid has no Cast control or discovery permission prompt',
      (tester) async {
    final service = ChromeCastService();
    await service.initialize();
    service.startDiscovery();
    expect(service.isConnected, isFalse);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ChromeCastButton(chromeCastService: service))));
    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    service.dispose();
  }, skip: supportsGoogleCast);
}
