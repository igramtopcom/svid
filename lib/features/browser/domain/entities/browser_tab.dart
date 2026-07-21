/// Represents a single browser tab
class BrowserTab {
  final String id;
  final String url;
  final String title;
  final bool isActive;
  final bool isPrivate;
  final bool canGoBack;
  final bool canGoForward;
  final DateTime createdAt;

  const BrowserTab({
    required this.id,
    required this.url,
    this.title = '',
    this.isActive = false,
    this.isPrivate = false,
    this.canGoBack = false,
    this.canGoForward = false,
    required this.createdAt,
  });

  BrowserTab copyWith({
    String? url,
    String? title,
    bool? isActive,
    bool? isPrivate,
    bool? canGoBack,
    bool? canGoForward,
  }) {
    return BrowserTab(
      id: id,
      url: url ?? this.url,
      title: title ?? this.title,
      isActive: isActive ?? this.isActive,
      isPrivate: isPrivate ?? this.isPrivate,
      canGoBack: canGoBack ?? this.canGoBack,
      canGoForward: canGoForward ?? this.canGoForward,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'title': title,
        'isActive': isActive,
        'isPrivate': isPrivate,
        'canGoBack': canGoBack,
        'canGoForward': canGoForward,
        'createdAt': createdAt.toIso8601String(),
      };

  factory BrowserTab.fromJson(Map<String, dynamic> json) => BrowserTab(
        id: json['id'] as String,
        url: json['url'] as String,
        title: json['title'] as String? ?? '',
        isActive: json['isActive'] as bool? ?? false,
        isPrivate: json['isPrivate'] as bool? ?? false,
        canGoBack: json['canGoBack'] as bool? ?? false,
        canGoForward: json['canGoForward'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrowserTab &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
