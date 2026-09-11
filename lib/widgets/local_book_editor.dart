import 'package:aradia/resources/models/local_audiobook.dart';
import 'package:aradia/resources/services/audio_handler_provider.dart';
import 'package:aradia/resources/services/local/book_cover_search.dart';
import 'package:aradia/resources/services/local/cover_image_service.dart';
import 'package:aradia/resources/services/local/local_book_metadata.dart';
import 'package:aradia/utils/media_helper.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LocalBookEditor extends StatefulWidget {
  const LocalBookEditor({super.key, required this.audiobook, this.onUpdated});
  final LocalAudiobook audiobook;
  final VoidCallback? onUpdated;
  @override
  State<LocalBookEditor> createState() => _LocalBookEditorState();
}

class _LocalBookEditorState extends State<LocalBookEditor> {
  late final _title = TextEditingController(text: widget.audiobook.title);
  late final _author = TextEditingController(text: widget.audiobook.author);
  List<String> _covers = [];
  String? _selected;
  String? _currentCover;
  String? _error;
  bool _defaultCover = false;
  bool _searching = false;
  bool _saving = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    resolveCoverForLocal(widget.audiobook).then((value) {
      if (mounted) setState(() => _currentCover = value);
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final request = ++_request;
    setState(() {
      _searching = true;
      _error = null;
      _selected = null;
      _covers = [];
    });
    try {
      final results =
          await BookCoverSearch.instance.search(_title.text, _author.text);
      if (!mounted || request != _request) return;
      setState(() {
        _covers = results;
        if (results.isEmpty) {
          _error =
              'No covers found. Try a shorter title or remove the author and search again.';
        }
      });
    } catch (error) {
      if (mounted && request == _request) setState(() => _error = '$error');
    } finally {
      if (mounted && request == _request) setState(() => _searching = false);
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a title.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Download first so a failed cover download leaves the existing book intact.
      final cover = _selected == null
          ? null
          : await BookCoverSearch.instance.download(_selected!);
      final book = await LocalBookMetadata.save(
          widget.audiobook, _title.text, _author.text);
      if (cover != null) await mapCoverForLocal(book, cover);
      if (_defaultCover) {
        for (final key in {
          MediaHelper.bookKeyForLocal(book),
          book.id,
          MediaHelper.decodePath(book.folderPath)
        }) {
          await removeCoverMapping(key);
        }
      }
      await LocalBookMetadata.updateCover(
          book, await resolveCoverForLocal(book));
      if (!mounted) return;
      await context
          .read<AudioHandlerProvider>()
          .audioHandler
          .refreshBookMetadata(book);
      widget.onUpdated?.call();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit audiobook'),
      content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                  controller: _title,
                  enabled: !_saving,
                  decoration: const InputDecoration(labelText: 'Title')),
              TextField(
                  controller: _author,
                  enabled: !_saving,
                  decoration: const InputDecoration(labelText: 'Author')),
              const SizedBox(height: 16),
              if (_currentCover != null && !_defaultCover)
                Center(
                    child: Image(
                  image: coverProvider(_currentCover!),
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.headphones),
                )),
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                    onPressed: _searching || _saving ? null : _search,
                    icon: const Icon(Icons.search),
                    label: const Text('Search covers')),
                TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                              _defaultCover = true;
                              _selected = null;
                            }),
                    child: Text(_defaultCover
                        ? 'Default cover selected'
                        : 'Use default cover')),
              ]),
              if (_searching) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
              if (_covers.isNotEmpty)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8),
                  itemCount: _covers.length,
                  itemBuilder: (context, index) {
                    final url = _covers[index];
                    return InkWell(
                        onTap: _saving
                            ? null
                            : () => setState(() {
                                  _selected = url;
                                  _defaultCover = false;
                                }),
                        child: Stack(fit: StackFit.expand, children: [
                          Image(
                              image: coverProvider(url),
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.broken_image_outlined)),
                          if (_selected == url)
                            Align(
                                alignment: Alignment.topRight,
                                child: Icon(Icons.check_circle,
                                    color:
                                        Theme.of(context).colorScheme.primary)),
                        ]));
                  },
                ),
            ],
          ))),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save changes')),
      ],
    );
  }
}
