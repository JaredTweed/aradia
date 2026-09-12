import 'package:flutter/material.dart';

/// The selection describes which chapters should remain on this device.
class ChapterSelectionDialog extends StatefulWidget {
  final List<Map<String, dynamic>> chapters;
  final Set<int> downloaded;

  const ChapterSelectionDialog({
    super.key,
    required this.chapters,
    required this.downloaded,
  });

  @override
  State<ChapterSelectionDialog> createState() => _ChapterSelectionDialogState();
}

class _ChapterSelectionDialogState extends State<ChapterSelectionDialog> {
  late final Set<int> selected = {...widget.downloaded};

  @override
  Widget build(BuildContext context) {
    final downloads = selected.difference(widget.downloaded).length;
    final deletions = widget.downloaded.difference(selected).length;
    final allSelected = selected.length == widget.chapters.length;
    final label = [
      if (downloads > 0) 'Download $downloads',
      if (deletions > 0) 'Delete $deletions',
    ].join('\n');
    return AlertDialog(
      title: const Text('Manage chapters'),
      content: SizedBox(
        width: 480,
        height: MediaQuery.sizeOf(context).height * 0.5,
        child: Column(children: [
          const Text('Select the chapters to keep on this device.'),
          Row(children: [
            TextButton(
              onPressed: () => setState(() {
                selected.clear();
                if (!allSelected) {
                  selected
                      .addAll(List.generate(widget.chapters.length, (i) => i));
                }
              }),
              child: Text(allSelected ? 'Select none' : 'Select all'),
            ),
            TextButton(
              onPressed: () => setState(() {
                selected
                  ..clear()
                  ..addAll(widget.downloaded);
              }),
              child: const Text('Reset'),
            ),
          ]),
          Expanded(
              child: ListView.builder(
            itemCount: widget.chapters.length,
            itemBuilder: (context, i) => CheckboxListTile(
              key: ValueKey('chapter-$i'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              value: selected.contains(i),
              onChanged: (value) => setState(() {
                if (value == true) {
                  selected.add(i);
                } else {
                  selected.remove(i);
                }
              }),
              title: Text(
                  widget.chapters[i]['title'] as String? ?? 'Chapter ${i + 1}'),
              subtitle: Text(widget.downloaded.contains(i)
                  ? 'Available offline'
                  : 'Not downloaded'),
              secondary: widget.downloaded.contains(i)
                  ? const Tooltip(
                      message: 'Downloaded',
                      child: Icon(Icons.check_circle_outline))
                  : const SizedBox(width: 24),
            ),
          )),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: label.isEmpty
              ? null
              : () => Navigator.pop(context, Set<int>.of(selected)),
          child: Text(label.isEmpty ? 'Apply' : label,
              textAlign: TextAlign.center),
        ),
      ],
    );
  }
}
