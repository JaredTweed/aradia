import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/history_of_audiobook.dart';
import 'package:aradia/resources/services/recommendation_service.dart';
import 'package:aradia/utils/app_events.dart';
import 'package:aradia/widgets/audiobook_item.dart';

class RecommendedBooksSection extends StatefulWidget {
  const RecommendedBooksSection({super.key});
  @override
  State<RecommendedBooksSection> createState() =>
      _RecommendedBooksSectionState();
}

class _RecommendedBooksSectionState extends State<RecommendedBooksSection> {
  late Future<List<Audiobook>> _books;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Timer? _debounce;
  String _historyKey = '';
  @override
  void initState() {
    super.initState();
    _books = RecommendationService().getRecommendations();
    _subscriptions.add(HistoryOfAudiobook().historyStream.listen((history) {
      final key = history
          .map((item) =>
              '${item.audiobook.id}:${item.index > 0 || item.position >= 120000}')
          .toList()
        ..sort();
      if (key.join('|') != _historyKey) {
        _historyKey = key.join('|');
        _refresh();
      }
    }));
    _subscriptions
        .add(AppEvents.languagesChanged.stream.listen((_) => _refresh()));
    for (final name in [
      'recommened_audiobooks_box',
      'favourite_audiobooks_box'
    ]) {
      Hive.openBox(name).then((box) {
        if (mounted) _subscriptions.add(box.watch().listen((_) => _refresh()));
      });
    }
  }

  void _refresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _books = RecommendationService().getRecommendations();
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Recommended for you',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
        SizedBox(
            height: 250,
            child: FutureBuilder<List<Audiobook>>(
                future: _books,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                        child: TextButton.icon(
                            onPressed: _refresh,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry recommendations')));
                  }
                  final books = snapshot.data ?? [];
                  if (books.isEmpty) {
                    return const Center(
                        child: Text(
                            'Try adding genres in Settings to discover more books.'));
                  }
                  return ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: books.length,
                      itemBuilder: (context, i) =>
                          AudiobookItem(audiobook: books[i], width: 175));
                })),
      ]);
}
