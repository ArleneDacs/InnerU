class Comment {
  String commentId;
  String username;
  String content;
  String timestamp;
  String userId; // Add this field

  Comment({
    required this.commentId,
    required this.username,
    required this.content,
    required this.timestamp,
    required this.userId, // Include in constructor
  });

  Map<String, dynamic> toJson() {
    return {
      'commentId': commentId,
      'username': username,
      'content': content,
      'timestamp': timestamp,
      'userId': userId, // Add to JSON
    };
  }

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      commentId: json['commentId'],
      username: json['username'],
      content: json['content'],
      timestamp: json['timestamp'],
      userId: json['userId'] ?? "unknown", // Add from JSON
    );
  }
}
