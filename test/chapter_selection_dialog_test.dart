import 'package:aradia/screens/download_audiobook/widget/chapter_selection_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> open(WidgetTester tester, Set<int> downloaded,
      ValueChanged<Set<int>?> onResult) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return TextButton(
        onPressed: () async => onResult(await showDialog<Set<int>>(
          context: context,
          builder: (_) => ChapterSelectionDialog(
            chapters: List.generate(3, (i) => {'title': 'Chapter ${i + 1}'}),
            downloaded: downloaded,
          ),
        )),
        child: const Text('Open'),
      );
    })));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('mixed additions and deletions are applied together',
      (tester) async {
    Set<int>? result;
    await open(tester, {0, 1}, (value) => result = value);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(find.byIcon(Icons.check_circle_outline), findsNWidgets(2));
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(ValueKey('chapter-$i')));
      await tester.pump();
    }
    expect(find.text('Download 1\nDelete 2'), findsOneWidget);
    expect(result, isNull);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(result, {2});
  });

  testWidgets(
      'select all toggles to none and reset restores downloaded chapters',
      (tester) async {
    await open(tester, {1}, (_) {});
    await tester.tap(find.text('Select all'));
    await tester.pump();
    expect(find.text('Download 2'), findsOneWidget);
    await tester.tap(find.text('Select none'));
    await tester.pump();
    expect(find.text('Delete 1'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pump();
    final tiles = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .toList();
    expect(tiles.map((tile) => tile.value), [false, true, false]);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
  });

  testWidgets('cancel discards a pending deletion', (tester) async {
    var returned = false;
    Set<int>? result = {99};
    await open(tester, {0, 1, 2}, (value) {
      returned = true;
      result = value;
    });
    await tester.tap(find.text('Select none'));
    await tester.pump();
    expect(find.text('Delete 3'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(returned, isTrue);
    expect(result, isNull);
  });
}
