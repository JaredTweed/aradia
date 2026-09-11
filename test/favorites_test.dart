import 'dart:io';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/screens/audiobook_details/bloc/audiobook_details_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  test('removing a favorite does not lose the watched book identity', () async {
    final directory = await Directory.systemTemp.createTemp('aradia_favorites');
    Hive.init(directory.path);
    final box = await Hive.openBox('favourite_audiobooks_box');
    final bloc = AudiobookDetailsBloc();
    final book = Audiobook.fromMap({'id': 'book', 'title': 'Book'});
    bloc.add(GetFavouriteStatus(book));
    await Future<void>.delayed(Duration.zero);
    await box.put(book.id, book.toMap());
    await Future<void>.delayed(Duration.zero);
    expect((bloc.state as AudiobookDetailsFavourite).isFavourite, true);
    await box.delete(book.id);
    await Future<void>.delayed(Duration.zero);
    expect((bloc.state as AudiobookDetailsFavourite).isFavourite, false);
    await box.put(book.id, book.toMap());
    await Future<void>.delayed(Duration.zero);
    expect((bloc.state as AudiobookDetailsFavourite).isFavourite, true);
    await bloc.close();
    await Hive.close();
    await directory.delete(recursive: true);
  });
}
