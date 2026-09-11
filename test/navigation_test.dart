import 'dart:io';
import 'package:aradia/widgets/player_back_scope.dart';
import 'package:aradia/widgets/scaffold_with_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:we_slide/we_slide.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('aradia_navigation');
    Hive.init(directory.path);
    await Hive.openBox('playing_audiobook_details_box');
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  testWidgets(
      'Back collapses player before popping details; search returns home',
      (tester) async {
    final controller = WeSlideController();
    final router = GoRouter(initialLocation: '/home', routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => ScaffoldWithNavBar(shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/home',
                builder: (_, __) =>
                    const PlayerBackScope(child: Text('Home page')),
                routes: [
                  GoRoute(
                      path: 'details',
                      builder: (_, __) =>
                          const PlayerBackScope(child: Text('Details page'))),
                ])
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/search',
                builder: (_, __) =>
                    const PlayerBackScope(child: Text('Search page')))
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/download',
                builder: (_, __) =>
                    const PlayerBackScope(child: Text('Downloads page')))
          ]),
        ],
      ),
    ]);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: controller, child: MaterialApp.router(routerConfig: router)));
    router.push('/home/details');
    await tester.pumpAndSettle();
    controller.show();
    await tester.pumpAndSettle();
    expect(await router.routerDelegate.popRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(controller.isOpened, isFalse);
    expect(find.text('Details page'), findsOneWidget);
    await router.routerDelegate.popRoute();
    await tester.pumpAndSettle();
    expect(find.text('Home page'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    expect(find.text('Search page'), findsOneWidget);
    expect(await router.routerDelegate.popRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Home page'), findsOneWidget);
    controller.show();
    await tester.pumpAndSettle();
    expect(await router.routerDelegate.popRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(controller.isOpened, isFalse);
    expect(await router.routerDelegate.popRoute(), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    controller.dispose();
  });
}
