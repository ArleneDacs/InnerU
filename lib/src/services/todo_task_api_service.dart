import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class TodoTaskApiService {
  TodoTaskApiService._();

  static final TodoTaskApiService instance = TodoTaskApiService._();

  final ApiClient _api = ApiClient.instance;
  String? get _token => AuthService.instance.currentSession?.token;

  Future<List<Map<String, dynamic>>> fetchTasks() async {
    final response = await _api.getJson('/api/todo-tasks', token: _token);
    final tasks = response['tasks'];
    if (tasks is! List) return const <Map<String, dynamic>>[];
    return tasks
        .whereType<Map>()
        .map((task) => Map<String, dynamic>.from(task))
        .toList();
  }

  Future<Map<String, dynamic>> saveTask(Map<String, dynamic> payload) async {
    final response = await _api.postJson('/api/todo-tasks', payload, token: _token);
    final task = response['task'];
    if (task is Map<String, dynamic>) {
      return task;
    }
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> updateTask(
    String taskId,
    Map<String, dynamic> payload,
  ) async {
    final response = await _api.patchJson('/api/todo-tasks/$taskId', payload, token: _token);
    final task = response['task'];
    if (task is Map<String, dynamic>) {
      return task;
    }
    return <String, dynamic>{};
  }

  Future<void> deleteTask(String taskId) async {
    await _api.deleteJson('/api/todo-tasks/$taskId', token: _token);
  }
}
