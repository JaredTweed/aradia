import 'package:aradia/screens/audiobook_details/widgets/description_text.dart';
import 'package:aradia/resources/designs/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'empty descriptions disappear and short descriptions have no expansion link',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: DescriptionText(description: '<p> </p>'))));
    expect(find.byType(TextButton), findsNothing);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: DescriptionText(
                description: 'A short &amp; useful description.'))));
    await tester.pump();
    expect(find.text('A short & useful description.'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 200,
                child: DescriptionText(
                    description: List.filled(80, 'A much longer description.')
                        .join(' '))))));
    await tester.pump();
    expect(find.text('Read more'), findsOneWidget);
  });
  test('all surface roles remain neutral in light and dark themes', () {
    for (final theme in [Themes.lightTheme, Themes.darkTheme]) {
      final c = theme.colorScheme;
      for (final color in [
        c.surface,
        c.surfaceContainer,
        c.surfaceContainerLow,
        c.surfaceContainerHigh,
        c.surfaceContainerHighest,
        c.surfaceDim,
        c.surfaceBright
      ]) {
        expect(color.r, color.g);
        expect(color.g, color.b);
      }
    }
  });
}
