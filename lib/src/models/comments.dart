class Comment {
  String commentId;
  String username;
  String content;
  String timestamp;

  Comment({
    required this.commentId,
    required this.username,
    required this.content,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'commentId': commentId,
      'username': username,
      'content': content,
      'timestamp': timestamp,
    };
  }

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      commentId: json['commentId'],
      username: json['username'],
      content: json['content'],
      timestamp: json['timestamp'],
    );
  }
}
