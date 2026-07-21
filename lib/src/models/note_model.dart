import 'dart:math';

class Note {
  String id;
  String userId;
  String username;
  String title;
  List<Map<String, String>> note; // Stores both text and images
  int color;
  DateTime createdAt;
  String category;
  bool saved; // Add the saved field
  String companyId;
  String companyCode;
  String companyName;

  Note({
    required this.id,
    required this.userId,
    required this.username,
    required this.title,
    required this.note,
    this.color = 0xFFFFFFFF,
    required this.createdAt,
    required this.category,
    this.saved = false, // Default to false
    this.companyId = '',
    this.companyCode = '',
    this.companyName = '',
  });

  factory Note.fromMap(Map<String, dynamic> data) {
    final rawCreatedAt = data['createdAt'] ?? data['created_at'];
    DateTime createdAt;
    if (rawCreatedAt is String) {
      createdAt = DateTime.tryParse(rawCreatedAt) ?? DateTime.now();
    } else if (rawCreatedAt is DateTime) {
      createdAt = rawCreatedAt;
    } else if (rawCreatedAt is int) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(rawCreatedAt);
    } else {
      createdAt = DateTime.now();
    }

    return Note(
      id: data['id'] ?? '',
      username: data['username'] ?? '',
      title: data['title'] ?? '',
      note: List<Map<String, String>>.from(
        (data['note'] as List<dynamic>)
            .map((item) => Map<String, String>.from(item)),
      ),
      color: data['color'] is int
          ? data['color']
          : int.tryParse(data['color']?.toString() ?? '') ?? 0xFFFFFFFF,
      createdAt: createdAt,
      category: data['category'] ?? '',
      userId: data['userId'] ?? '',
      saved: data['saved'] ?? false, // Default to false if missing
      companyId:
          (data['companyId'] as String?)?.trim() ??
          (data['activeCompanyId'] as String?)?.trim() ??
          '',
      companyCode:
          (data['companyCode'] as String?)?.trim() ??
          (data['activeCompanyCode'] as String?)?.trim() ??
          '',
      companyName:
          (data['companyName'] as String?)?.trim() ??
          (data['activeCompanyName'] as String?)?.trim() ??
          '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "username": username,
      "title": title,
      "note": note,
      "color": color,
      "createdAt": createdAt,
      "category": category,
      "userId": userId,
      "saved": saved, // Include saved field
      "companyId": companyId,
      "companyCode": companyCode,
      "companyName": companyName,
    };
  }
}

int generateRandomLightShade() {
  Random random = Random();

  // Define base colors
  List<int> baseColors = [
    0xFF80C8BC, // Teal
    0xFFEFD199, // Yellow
    0xFF62A782, // Greenish teal
    0xFF5EC0CA // Light blue cyan
  ];

  int baseColor = baseColors[random.nextInt(baseColors.length)];

  int red = (baseColor >> 16) & 0xFF;
  int green = (baseColor >> 8) & 0xFF;
  int blue = baseColor & 0xFF;

  double lightenFactor =
      0.3 + random.nextDouble() * 0.4; // Adjust how much lighter (0.3 - 0.7)

  red = (red + (255 - red) * lightenFactor).toInt().clamp(0, 255);
  green = (green + (255 - green) * lightenFactor).toInt().clamp(0, 255);
  blue = (blue + (255 - blue) * lightenFactor).toInt().clamp(0, 255);

  return (0xFF << 24) | (red << 16) | (green << 8) | blue;
}
