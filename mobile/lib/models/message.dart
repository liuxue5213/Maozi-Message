class Message {
  final String id;
  final String content;
  final String authorName;
  final String authorId;
  final String color;
  final String bgColor;
  final String mood;
  final bool isAnonymous;
  final int likesCount;
  final int dislikesCount;
  final int repliesCount;
  final String createdAt;
  final String? myVote;
  final List<Reply> replies;

  Message({
    required this.id,
    required this.content,
    required this.authorName,
    this.authorId = '',
    this.color = '#ffffff',
    this.bgColor = 'rgba(0,0,0,0.6)',
    this.mood = 'neutral',
    this.isAnonymous = true,
    this.likesCount = 0,
    this.dislikesCount = 0,
    this.repliesCount = 0,
    required this.createdAt,
    this.myVote,
    this.replies = const [],
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] ?? '',
      content: json['content'] ?? '',
      authorName: json['author_name'] ?? '匿名',
      authorId: json['author_id'] ?? '',
      color: json['color'] ?? '#ffffff',
      bgColor: json['bg_color'] ?? 'rgba(0,0,0,0.6)',
      mood: json['mood'] ?? 'neutral',
      isAnonymous: (json['is_anonymous'] ?? 1) == 1,
      likesCount: json['real_likes'] ?? json['likes_count'] ?? 0,
      dislikesCount: json['real_dislikes'] ?? json['dislikes_count'] ?? 0,
      repliesCount: json['replies_count'] ?? 0,
      createdAt: json['created_at'] ?? '',
      myVote: json['my_vote'],
      replies: (json['replies'] as List<dynamic>?)
              ?.map((r) => Reply.fromJson(r))
              .toList() ??
          [],
    );
  }
}

class Reply {
  final String id;
  final String messageId;
  final String content;
  final String authorName;
  final int likesCount;
  final int dislikesCount;
  final String createdAt;
  final String? myVote;

  Reply({
    required this.id,
    required this.messageId,
    required this.content,
    required this.authorName,
    this.likesCount = 0,
    this.dislikesCount = 0,
    required this.createdAt,
    this.myVote,
  });

  factory Reply.fromJson(Map<String, dynamic> json) {
    return Reply(
      id: json['id'] ?? '',
      messageId: json['message_id'] ?? '',
      content: json['content'] ?? '',
      authorName: json['author_name'] ?? '匿名',
      likesCount: json['real_likes'] ?? json['likes_count'] ?? 0,
      dislikesCount: json['real_dislikes'] ?? json['dislikes_count'] ?? 0,
      createdAt: json['created_at'] ?? '',
      myVote: json['my_vote'],
    );
  }
}
