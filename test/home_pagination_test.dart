import 'package:aradia/resources/archive_api.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/screens/home/bloc/home_bloc.dart';
import 'package:aradia/screens/home/widgets/my_audiobooks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

class PageApi extends ArchiveApi {
  final calls = <int>[];
  @override
  Future<Either<String, List<Audiobook>>> getLatestAudiobook(
      int page, int rows) async {
    calls.add(page);
    if (calls.length == 2) return const Left('temporary outage');
    return Right(
        page == 1 ? [Audiobook.empty().copyWith(id: '1', title: 'One')] : []);
  }
}

void main() {
  testWidgets(
      'pagination retries the same page, ends cleanly, and preserves the owner controller',
      (tester) async {
    final api = PageApi();
    final bloc = HomeBloc(archiveApi: api);
    final controller = ScrollController();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MyAudiobooks(
                title: 'Latest',
                homeBloc: bloc,
                fetchType: AudiobooksFetchType.latest,
                rowsPerPage: 1,
                scrollController: controller))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Load more'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(api.calls, [1, 2, 2]);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.addListener(
        () {}); // Child must not dispose an externally owned controller.
    controller.dispose();
    await tester.runAsync(bloc.close);
  });
}
