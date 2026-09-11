import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:html/parser.dart' as html;

class DescriptionText extends StatefulWidget {
  static String plainText(String? value) =>
      html.parseFragment(value ?? '').text?.trim() ?? '';
  static bool hasDescription(String? value) => !{
        '',
        'n/a',
        'null',
        'no description',
        'no description available'
      }.contains(plainText(value).toLowerCase());
  final String description;
  const DescriptionText({
    super.key,
    required this.description,
  });

  @override
  State<DescriptionText> createState() => _DescriptionTextState();
}

class _DescriptionTextState extends State<DescriptionText> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final description = DescriptionText.plainText(widget.description);
    if (!DescriptionText.hasDescription(description)) {
      return const SizedBox.shrink();
    }
    final style = GoogleFonts.ubuntu(fontSize: 13);
    return LayoutBuilder(builder: (context, constraints) {
      final painter = TextPainter(
          text: TextSpan(text: description, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 4)
        ..layout(maxWidth: constraints.maxWidth);
      final expandable = painter.didExceedMaxLines;
      painter.dispose();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(description,
            style: style,
            maxLines: !_isExpanded && expandable ? 4 : null,
            overflow:
                !_isExpanded && expandable ? TextOverflow.ellipsis : null),
        if (expandable)
          TextButton(
            onPressed: () => setState(() => _isExpanded = !_isExpanded),
            child: Text(_isExpanded ? 'Read less' : 'Read more'),
          ),
      ]);
    });
  }
}
