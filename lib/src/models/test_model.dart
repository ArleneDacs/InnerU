class TestModel {
  String id;
  String testName;
  String testNote;
  final DateTime createdAt;

  TestModel(
      {required this.id,
      required this.testName,
      required this.createdAt,
      required this.testNote});
}
