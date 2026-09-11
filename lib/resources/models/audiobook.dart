class Audiobook {
  static String _text(dynamic value, [String fallback = '']) => value == null
      ? fallback
      : value is List
          ? value.map((item) => item.toString()).join(', ')
          : value.toString();
  static int _integer(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  static double? _rating(dynamic value) =>
      value == null ? null : double.tryParse('$value');

  final String title;
  final String id;
  final String? description;
  final String? totalTime;
  final String? author;
  final DateTime? date;
  final int? downloads;
  final List<dynamic>? subject;
  final int? size;
  final double? rating;
  final int? reviews;
  final String lowQCoverImage;
  final String? language;
  final String? origin;

  Audiobook.empty()
      : title = '',
        id = '',
        description = '',
        totalTime = '',
        author = '',
        date = null,
        downloads = 0,
        subject = [],
        size = 0,
        rating = 0,
        reviews = 0,
        lowQCoverImage = '',
        language = '',
        origin = '';

  Audiobook.fromJson(Map jsonAudiobook)
      : id = _text(jsonAudiobook["identifier"]),
        title = _text(jsonAudiobook["title"]),
        totalTime = _text(jsonAudiobook["runtime"]),
        author = _text(jsonAudiobook["creator"], 'Unknown'),
        date = jsonAudiobook['date'] != null
            ? DateTime.tryParse(_text(jsonAudiobook["date"]))
            : null,
        downloads = _integer(jsonAudiobook["downloads"]),
        subject = jsonAudiobook["subject"] == null
            ? []
            : jsonAudiobook["subject"] is String
                ? [jsonAudiobook["subject"]]
                : (jsonAudiobook["subject"] as List)
                    .where((s) => !["librivox", "audiobooks", "audiobook"]
                        .contains(s.toString().toLowerCase()))
                    .toList(),
        size = _integer(jsonAudiobook["item_size"]),
        rating = jsonAudiobook["avg_rating"] != null
            ? _rating(jsonAudiobook["avg_rating"])
            : null,
        reviews = _integer(jsonAudiobook["num_reviews"]),
        description = _text(jsonAudiobook["description"]),
        language = _text(jsonAudiobook["language"], 'en'),
        lowQCoverImage =
            "https://archive.org/services/get-item-image.php?identifier=${jsonAudiobook['identifier']}",
        origin = "librivox";

  static List<Audiobook> fromJsonArray(List jsonAudiobook) {
    List<Audiobook> audiobooks = <Audiobook>[];
    for (var book in jsonAudiobook) {
      if (book["title"] != null && book["creator"] != null) {
        String title = book["title"].toString();
        String creator = book["creator"].toString();

        if (!title.toLowerCase().contains("thumbs") &&
            !creator.toLowerCase().contains("librivox") &&
            title != 'null') {
          audiobooks.add(Audiobook.fromJson(book));
        }
      }
    }
    return audiobooks;
  }

  Map<dynamic, dynamic> toMap() {
    return {
      "title": title,
      "id": id,
      "description": description ?? '',
      "totalTime": totalTime ?? '',
      "author": author ?? '',
      "date": date?.toIso8601String(),
      "downloads": downloads ?? 0,
      "subject": subject ?? [],
      "size": size ?? 0,
      "rating": rating ?? 0.0,
      "reviews": reviews ?? 0,
      "lowQCoverImage": lowQCoverImage,
      "language": language ?? '',
      "origin": origin ?? '',
    };
  }

  Audiobook.fromMap(Map<dynamic, dynamic> map)
      : title = map["title"] ?? '',
        id = map["id"] ?? '',
        description = map["description"] ?? '',
        totalTime = map["totalTime"] ?? '',
        author = map["author"] ?? '',
        date = map["date"] != null ? DateTime.tryParse(map["date"]) : null,
        downloads = map["downloads"] ?? 0,
        subject = map["subject"] ?? [],
        size = map["size"] ?? 0,
        rating = map["rating"] != null
            ? double.parse(map["rating"].toString())
            : 0.0,
        reviews = map["reviews"] ?? 0,
        lowQCoverImage = map["lowQCoverImage"] ?? '',
        language = map["language"] ?? '',
        origin = map["origin"] ?? '';

  Map<String, dynamic> toJson() {
    return {
      "title": title,
      "id": id,
      "description": description,
      "totalTime": totalTime,
      "author": author,
      "date": date?.toIso8601String(),
      "downloads": downloads,
      "subject": subject,
      "size": size,
      "rating": rating,
      "reviews": reviews,
      "lowQCoverImage": lowQCoverImage,
      "language": language,
      "origin": origin,
    };
  }

  Audiobook copyWith({
    String? title,
    String? id,
    String? description,
    String? totalTime,
    String? author,
    DateTime? date,
    int? downloads,
    List<String>? subject,
    int? size,
    double? rating,
    int? reviews,
    String? lowQCoverImage,
    String? language,
    String? origin,
  }) {
    return Audiobook.fromMap({
      'title': title ?? this.title,
      'id': id ?? this.id,
      'description': description ?? this.description,
      'totalTime': totalTime ?? this.totalTime,
      'author': author ?? this.author,
      'date': (date ?? this.date)?.toIso8601String(),
      'downloads': downloads ?? this.downloads,
      'subject': subject ?? this.subject,
      'size': size ?? this.size,
      'rating': rating ?? this.rating,
      'reviews': reviews ?? this.reviews,
      'lowQCoverImage': lowQCoverImage ?? this.lowQCoverImage,
      'language': language ?? this.language,
      'origin': origin ?? this.origin,
    });
  }
}
