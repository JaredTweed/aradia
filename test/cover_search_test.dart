import 'dart:convert';
import 'dart:io';
import 'package:aradia/resources/services/local/book_cover_search.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('filename cleanup and matching reject unrelated catalogue results', () {
    expect(
        BookCoverSearch.searchTitle('Sahil Bloom - The 5 Types of Wealth.m4b'),
        'The 5 Types of Wealth');
    expect(BookCoverSearch.searchTitle('Land Power: Who Has It, Who Doesn’t'),
        'Land Power');
    expect(
        BookCoverSearch.relevance(
            'Land Power', 'Land Power', '', 'Michael Albertus'),
        greaterThan(0));
    expect(
        BookCoverSearch.relevance(
            'Land Power', 'A Promised Land (Unabridged)', '', 'Barack Obama'),
        0);
    expect(
        BookCoverSearch.relevance(
            'Land Power', 'Trade, Land, Power', '', 'Daniel Richter'),
        0);
    expect(
        BookCoverSearch.relevance(
            'Ha!',
            'Ha!: The Science of When We Laugh and Why',
            'Scott Weems',
            'Scott Weems'),
        greaterThan(0));
  });
  test(
      'cover search handles catalogues independently and caches successful searches',
      () async {
    var calls = 0;
    final search = BookCoverSearch(client: MockClient((request) async {
      calls++;
      if (request.url.host == 'itunes.apple.com') return http.Response('', 503);
      expect(request.url.queryParameters['title'], 'The Hobbit');
      expect(request.url.queryParameters.containsKey('author'), false);
      return http.Response(
          jsonEncode({
            'docs': [
              {'cover_i': 123, 'title': 'The Hobbit'},
              {'cover_i': 123, 'title': 'The Hobbit'},
              {}
            ]
          }),
          200);
    }));
    expect(await search.search('The Hobbit.m4b', 'Unknown author'),
        ['https://covers.openlibrary.org/b/id/123-L.jpg?default=false']);
    await search.search('The Hobbit.m4b', 'Unknown author');
    expect(calls, 2);
  });
  test(
      'bad author metadata falls back to title and outage is not reported as no results',
      () async {
    final search = BookCoverSearch(client: MockClient((request) async {
      if (request.url.host == 'itunes.apple.com') {
        return http.Response('{"results":[]}', 200);
      }
      return http.Response(
          request.url.queryParameters.containsKey('author')
              ? '{"docs":[]}'
              : '{"docs":[{"cover_i":4,"title":"Book"}]}',
          200);
    }));
    expect(await search.search('Book', 'Bad metadata'), hasLength(1));
    final offline = BookCoverSearch(
        client: MockClient((_) async => http.Response('', 503)));
    await expectLater(
        offline.search('Book', ''), throwsA(isA<HttpException>()));
  });
}
