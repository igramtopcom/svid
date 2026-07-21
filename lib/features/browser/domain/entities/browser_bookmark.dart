/// Represents a saved browser bookmark
class BrowserBookmark {
  final String id;
  final String url;
  final String title;
  final DateTime createdAt;

  const BrowserBookmark({
    required this.id,
    required this.url,
    required this.title,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
      };

  factory BrowserBookmark.fromJson(Map<String, dynamic> json) =>
      BrowserBookmark(
        id: json['id'] as String,
        url: json['url'] as String,
        title: json['title'] as String? ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrowserBookmark &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
