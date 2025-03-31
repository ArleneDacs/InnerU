import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TodoList());  await Firebase.initializeApp();

}

class TodoList extends StatelessWidget {
  const TodoList({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Todo List Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.teal,
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.teal,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const TodoListScreen(),
    );
  }
}

// Task model
enum TaskTag {
  personal,
  professional,
  contribution,
  none
}

extension TaskTagExtension on TaskTag {
  String get displayName {
    switch (this) {
      case TaskTag.personal:
        return 'Personal'; // Shortened from 'Personal Goals'
      case TaskTag.professional:
        return 'Professional'; // Shortened from 'Professional Milestones'
      case TaskTag.contribution:
        return 'Contribution'; // Shortened from 'Contribution Goals'
      case TaskTag.none:
        return 'No Tag';
    }
  }

  String get fullDisplayName {
    switch (this) {
      case TaskTag.personal:
        return 'Personal Goals';
      case TaskTag.professional:
        return 'Professional Milestones';
      case TaskTag.contribution:
        return 'Contribution Goals';
      case TaskTag.none:
        return 'No Tag';
    }
  }

  // tag colors
  Color get color {
    switch (this) {
      case TaskTag.personal:
        return const Color(0xFF6D849A);
      case TaskTag.professional:
        return const Color(0xFFCE8F5A);
      case TaskTag.contribution:
        return const Color(0xFF90A17D);
      case TaskTag.none:
        return Colors.grey;
    }
  }
  
  // background tag colors
  Color get lightColor {
    switch (this) {
      case TaskTag.personal:
        return Color(0xFF7AF1FF); 
      case TaskTag.professional:
        return Color(0xFFFCE0AC); 
      case TaskTag.contribution:
        return Color(0xFFBBD1A2); 
      case TaskTag.none:
        return Color(0xFFF5F5F5); 
    }
  }
}

// create task
class Task {
  String id;
  String title;
  String description;
  bool isCompleted;
  DateTime dueDate;
  TaskTag tag;
  
  Task({
    required this.id,
    required this.title,
    this.description = '',
    required this.dueDate,
    this.isCompleted = false,
    this.tag = TaskTag.none,
  });
  
  // Convert to and from JSON
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'isCompleted': isCompleted,
    'dueDate': dueDate.toIso8601String(),
    'tag': tag.index,
  };
  
  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'],
    title: json['title'],
    description: json['description'] ?? '',
    isCompleted: json['isCompleted'] ?? false,
    dueDate: DateTime.parse(json['dueDate']),
    tag: TaskTag.values[json['tag'] ?? TaskTag.none.index],
  );
}

class FirestoreRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? get userId {
  final user = FirebaseAuth.instance.currentUser;
  return user?.uid; // Ensure user is logged in
}

  CollectionReference get tasksCollection {
    return _firestore.collection('users').doc(userId).collection('tasks');
  }

  Future<List<Task>> loadTasks() async {
  if (userId == null) {
    print('No user ID found. User not logged in?');
    return [];
  }

  print('Fetching tasks for user: $userId');

  try {
    final snapshot = await tasksCollection.orderBy('dueDate').get();

    if (snapshot.docs.isEmpty) {
      print('No tasks found for user $userId');
    }

    return snapshot.docs.map((doc) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      print('Fetched task: $data');
      return Task.fromJson(data);
    }).toList();
  } catch (e) {
    print('Error loading tasks: $e');
    return [];
  }
}


  Future<void> addTask(Task task) async {
    try {
      print('Adding task for user: $userId');
      print('Task Data: ${task.toJson()}');
      await tasksCollection.add(task.toJson());
      print('Task added successfully.');
    } catch (e) {
      print('Error adding task: $e');
    }
  }

  Future<void> updateTask(Task task) async {
    try {
      await tasksCollection.doc(task.id).update(task.toJson());
    } catch (e) {
      print('Error updating task: $e');
    }
  }

  Future<void> deleteTask(String id) async {
    try {
      await tasksCollection.doc(id).delete();
    } catch (e) {
      print('Error deleting task: $e');
    }
  }
  
  // Optional: Migration from local storage to Firestore
  Future<void> migrateFromLocalStorage() async {
    try {
      final localTasks = await TodoRepository.loadTasks();
      
      for (final task in localTasks) {
        await addTask(task);
      }
      
      print('Migration completed successfully!');
    } catch (e) {
      print('Error during migration: $e');
    }
  }
}

// Keep the original TodoRepository for migration purposes
class TodoRepository {
  static Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  static Future<File> get _localFile async {
    final path = await _localPath;
    return File('$path/todos.json');
  }

  static Future<List<Task>> loadTasks() async {
    try {
      final file = await _localFile;
      if (!await file.exists()) {
        return [];
      }
      
      final contents = await file.readAsString();
      final List<dynamic> jsonList = json.decode(contents);
      return jsonList.map((json) => Task.fromJson(json)).toList();
    } catch (e) {
      print('Error loading tasks: $e');
      return [];
    }
  }

  static Future<void> saveTasks(List<Task> tasks) async {
    try {
      final file = await _localFile;
      final jsonList = tasks.map((task) => task.toJson()).toList();
      await file.writeAsString(json.encode(jsonList));
    } catch (e) {
      print('Error saving tasks: $e');
    }
  }
}

// Main screen
class TodoListScreen extends StatefulWidget {
  const TodoListScreen({Key? key}) : super(key: key);

  @override
  _TodoListScreenState createState() => _TodoListScreenState();
}

class _TodoListScreenState extends State<TodoListScreen> {
  List<Task> _tasks = [];
  bool _isLoading = true;
  int _currentTabIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  
  // Create an instance of FirestoreRepository with fallback
  late final FirestoreRepository _repository;
  
  // Constructor with repository initialization
  _TodoListScreenState() {
    try {
      _repository = FirestoreRepository();
      print('Firestore repository initialized');
    } catch (e) {
      print('Error initializing Firestore repository: $e');
      // This catch block allows the app to continue even if Firestore initialization fails
    }
  }

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    setState(() {
      _isLoading = true;
    });
    
    // Load tasks from Firestore instead of local storage
    final tasks = await _repository.loadTasks();
    
    setState(() {
      _tasks = tasks;
      _isLoading = false;
    });
  }

  void _addTask(Task task) async {
  await _repository.addTask(task);
  await _loadTasks(); // Force refresh
}

  void _toggleTaskCompletion(String id) async {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index != -1) {
      final task = _tasks[index];
      task.isCompleted = !task.isCompleted;
      
      // Update task in Firestore
      await _repository.updateTask(task);
      
      setState(() {
        // Update UI
        _tasks[index] = task;
      });
    }
  }

  void _deleteTask(String id) async {
    // Delete task from Firestore
    await _repository.deleteTask(id);
    
    setState(() {
      _tasks.removeWhere((task) => task.id == id);
    });
  }

  // Show migration dialog - useful for first-time setup
  void _showMigrationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Migrate Data'),
        content: const Text('Would you like to migrate your existing tasks to Firebase Firestore?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              
              // Show loading indicator
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const Center(
                  child: CircularProgressIndicator(),
                ),
              );
              
              // Perform migration
              await _repository.migrateFromLocalStorage();
              
              // Dismiss loading indicator
              Navigator.pop(context);
              
              // Reload tasks
              _loadTasks();
              
              // Show success message
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Migration completed!')),
              );
            },
            child: const Text('MIGRATE'),
          ),
        ],
      ),
    );
  }

  List<Task> _getFilteredTasks() {
    final List<Task> filteredTasks;
    
    // First filter by search query
    final searchFiltered = _searchQuery.isEmpty
        ? _tasks
        : _tasks.where((task) => 
            task.title.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    
    // Then filter by tab
    switch (_currentTabIndex) {
      case 0: // All
        filteredTasks = searchFiltered;
        break;
      case 1: // Pending
        filteredTasks = searchFiltered.where((task) => !task.isCompleted).toList();
        break;
      case 2: // Completed
        filteredTasks = searchFiltered.where((task) => task.isCompleted).toList();
        break;
      default:
        filteredTasks = searchFiltered;
    }
    
    // Sort by due date (closest first)
    filteredTasks.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    
    return filteredTasks;
  }

  void _showAddTaskDialog() {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    TaskTag selectedTag = TaskTag.none;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('New Task'),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          actionsPadding: EdgeInsets.zero,
          backgroundColor: const Color(0xFFF2F0F7),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title field with list icon
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.list, color: Colors.brown[400], size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: titleController,
                        decoration: InputDecoration(
                          labelText: 'Title',
                          hintText: '',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
                          ),
                        ),
                        autofocus: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Description field with chat icon
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.only(top: 12),
                      child: Icon(Icons.chat_bubble_outline, color: Colors.brown[400], size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: descriptionController,
                        decoration: InputDecoration(
                          hintText: 'Description (optional)',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                        ),
                        maxLines: 3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.local_offer_outlined, color: Colors.brown[400], size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<TaskTag>(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            isExpanded: true,
                            value: selectedTag,
                            items: TaskTag.values.map((tag) {
                              return DropdownMenuItem<TaskTag>(
                                value: tag,
                                // Improve layout of dropdown items to prevent overflow
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 8.0), // Add padding to prevent overflow
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min, // Use minimum space needed
                                    children: [
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: tag == TaskTag.none ? Colors.grey : tag.color,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // Use Flexible to allow text to wrap or shrink if needed
                                      Flexible(
                                        child: Text(
                                          tag == TaskTag.none ? 'No Tag' : tag.displayName,
                                          overflow: TextOverflow.ellipsis, // Handle text overflow
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (newValue) {
                              setState(() {
                                selectedTag = newValue!;
                              });
                            },
                            // Constrain dropdown menu width
                            menuMaxHeight: 300,
                            hint: const Text('Add a task tag'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Due date selection
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_today, color: Colors.brown[400], size: 28),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Due Date',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        GestureDetector(
                          onTap: () async {
                            final DateTime? picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime.now(),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null && picked != selectedDate) {
                              setState(() {
                                selectedDate = picked;
                              });
                            }
                          },
                          child: Text(
                            DateFormat('EEE, MMM d, yyyy').format(selectedDate),
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // ADD button - gold/beige with white text (on the left)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ElevatedButton(
                        onPressed: () {
                          if (titleController.text.trim().isNotEmpty) {
                            _addTask(
                              Task(
                                id: DateTime.now().millisecondsSinceEpoch.toString(), // This will be replaced by Firestore's ID
                                title: titleController.text.trim(),
                                description: descriptionController.text.trim(),
                                dueDate: selectedDate,
                                tag: selectedTag,
                              ),
                            );
                            Navigator.pop(context);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEFD199), // Gold/beige color
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: const Text(
                          'ADD',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // CANCEL button - white with gray text (on the right)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.grey,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        child: const Text(
                          'CANCEL',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

@override
Widget build(BuildContext context) {
  final filteredTasks = _getFilteredTasks();
  
  return Scaffold(
    appBar: PreferredSize(
      preferredSize: const Size.fromHeight(50),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildCategoryButton('All', 0),
            _buildCategoryButton('Pending', 1, badge: _tasks.where((task) => !task.isCompleted).length),
            _buildCategoryButton('Completed', 2),
          ],
        ),
      ),
    ),
    backgroundColor: Colors.white,
    body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              // Search field
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search tasks...',
                    prefixIcon: const Icon(Icons.search, color: Colors.black),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(32),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFEFEEEE),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.grey),
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                                _searchQuery = '';
                              });
                            },
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),
                Expanded(
                  child: filteredTasks.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.check_circle_outline,
                                size: 80,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'No matching tasks found'
                                    : _currentTabIndex == 2
                                        ? 'No completed tasks yet'
                                        : 'No tasks yet',
                                style: const TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey,
                                ),
                              ),
                              if (_searchQuery.isEmpty && _currentTabIndex != 2)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: TextButton.icon(
                                    icon: const Icon(Icons.add_circle_outline, color: Colors.deepPurple),
                                    label: const Text('Add a new task', style: TextStyle(color: Colors.deepPurple)),
                                    onPressed: _showAddTaskDialog,
                                  ),
                                ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: filteredTasks.length,
                          itemBuilder: (context, index) {
                            final task = filteredTasks[index];
                            final bool isOverdue = !task.isCompleted && 
                                task.dueDate.isBefore(DateTime.now().subtract(const Duration(days: 1)));
                            
                            return Dismissible(
                              key: Key(task.id),
                              background: Container(
                                color: Colors.green,
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: const Icon(
                                  Icons.check_circle,
                                  color: Colors.white,
                                ),
                              ),
                              secondaryBackground: Container(
                                color: Colors.red,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: const Icon(
                                  Icons.delete,
                                  color: Colors.white,
                                ),
                              ),
                              confirmDismiss: (direction) async {
                                if (direction == DismissDirection.endToStart) {
                                  // Delete confirmation
                                  return await showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Delete Task'),
                                      content: const Text('Are you sure you want to delete this task?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, false),
                                          child: const Text('CANCEL'),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, true),
                                          child: const Text('DELETE'),
                                        ),
                                      ],
                                    ),
                                  );
                                } else {
                                  // Toggle completion without confirmation
                                  _toggleTaskCompletion(task.id);
                                  return false; // Don't actually dismiss
                                }
                              },
                              onDismissed: (direction) {
                                if (direction == DismissDirection.endToStart) {
                                  _deleteTask(task.id);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text('Task deleted'),
                                      action: SnackBarAction(
                                        label: 'UNDO',
                                        onPressed: () {
                                          _addTask(task);
                                        },
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: Card(
  margin: const EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 8,
  ),
  color: task.tag.lightColor,
  elevation: 0.5,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
  ),
  child: ListTile(
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 8,
    ),
    leading: Checkbox(
      value: task.isCompleted,
      onChanged: (value) {
        _toggleTaskCompletion(task.id);
      },
      shape: const CircleBorder(),
      checkColor: Colors.white,
      activeColor: Colors.deepPurple,
    ),
    title: Text(
      task.title,
      style: TextStyle(
        decoration: task.isCompleted
            ? TextDecoration.lineThrough
            : null,
        fontWeight: task.isCompleted
            ? FontWeight.normal
            : FontWeight.bold,
        color: task.isCompleted
            ? Colors.grey
            : null,
      ),
    ),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (task.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
            child: Text(
              task.description,
              style: TextStyle(
                color: task.isCompleted ? Colors.grey : Colors.black87,
                decoration: task.isCompleted ? TextDecoration.lineThrough : null,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        // Due date in its own row
        Padding(
          padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: 16,
                color: Colors.grey,
              ),
              const SizedBox(width: 4),
              Text(
                DateFormat('MMM d, yyyy').format(task.dueDate),
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        // Task tag in its own row
        if (task.tag != TaskTag.none)
          Padding(
            padding: const EdgeInsets.only(top: 2.0, bottom: 4.0),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: task.tag.color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                task.tag.displayName,
                style: TextStyle(
                  fontSize: 12,
                  color: task.tag.color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    ),
    // Replace the single trailing icon with a row of icons
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Edit button
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          onPressed: () {
            _editTask(task);
          },
        ),
        // Delete button
        IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final shouldDelete = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Delete Task'),
                content: const Text('Are you sure you want to delete this task?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('CANCEL'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('DELETE'),
                  ),
                ],
              ),
            );
            
            if (shouldDelete == true) {
              _deleteTask(task.id);
            }
          },
        ),
      ],
    ),
  ),
),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
      onPressed: _showAddTaskDialog,
      backgroundColor: const Color(0xFFEFD199),
      elevation: 2,
      shape: const CircleBorder(),
      child: const Icon(Icons.add, color: Colors.white),
    ),
   drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(
                color: Color(0xFF90A17D),
              ),
              child: Text(
                'Todo List',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_upload),
              title: const Text('Migrate Local Data to Firebase'),
              onTap: () {
                Navigator.pop(context);
                _showMigrationDialog();
              },
            ),
          ],
        ),
      ),
  );
}

void _editTask(Task task) {
  final titleController = TextEditingController(text: task.title);
  final descriptionController = TextEditingController(text: task.description);
  DateTime selectedDate = task.dueDate;
  TaskTag selectedTag = task.tag;

  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Edit Task'),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding: EdgeInsets.zero,
        backgroundColor: const Color(0xFFF2F0F7),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title field with list icon
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.list, color: Colors.brown[400], size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        labelText: 'Title',
                        hintText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
                        ),
                      ),
                      autofocus: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Description field with chat icon
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.only(top: 12),
                    child: Icon(Icons.chat_bubble_outline, color: Colors.brown[400], size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: descriptionController,
                      decoration: InputDecoration(
                        hintText: 'Description (optional)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                      ),
                      maxLines: 3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.local_offer_outlined, color: Colors.brown[400], size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<TaskTag>(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          isExpanded: true,
                          value: selectedTag,
                          items: TaskTag.values.map((tag) {
                            return DropdownMenuItem<TaskTag>(
                              value: tag,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: tag == TaskTag.none ? Colors.grey : tag.color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        tag == TaskTag.none ? 'No Tag' : tag.displayName,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (newValue) {
                            setState(() {
                              selectedTag = newValue!;
                            });
                          },
                          menuMaxHeight: 300,
                          hint: const Text('Add a task tag'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Due date selection
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.calendar_today, color: Colors.brown[400], size: 28),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Due Date',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      GestureDetector(
                        onTap: () async {
                          final DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null && picked != selectedDate) {
                            setState(() {
                              selectedDate = picked;
                            });
                          }
                        },
                        child: Text(
                          DateFormat('EEE, MMM d, yyyy').format(selectedDate),
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // SAVE button
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ElevatedButton(
                      onPressed: () {
                        if (titleController.text.trim().isNotEmpty) {
                          final updatedTask = Task(
                            id: task.id,
                            title: titleController.text.trim(),
                            description: descriptionController.text.trim(),
                            dueDate: selectedDate,
                            isCompleted: task.isCompleted,
                            tag: selectedTag,
                          );
                          
                          _updateTask(updatedTask);
                          Navigator.pop(context);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEFD199),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: const Text(
                        'SAVE',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                // CANCEL button
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.grey,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      child: const Text(
                        'CANCEL',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

void _updateTask(Task task) async {
  await _repository.updateTask(task);
  
  setState(() {
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index != -1) {
      _tasks[index] = task;
    }
  });
  
  // Show a confirmation message
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Task updated successfully')),
  );
}

Widget _buildCategoryButton(String category, int index, {int? badge}) {
  bool isSelected = index == _currentTabIndex;
  
  double buttonWidth;
  if (category == 'All') {
    buttonWidth = 80;
  } else if (category == 'Pending') {
    buttonWidth = 120;
  } else { // Completed
    buttonWidth = 120;
  }
  
  return GestureDetector(
    onTap: () {
      setState(() {
        _currentTabIndex = index;
      });
    },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 40,
      width: buttonWidth,
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF90A17D) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: isSelected
            ? [BoxShadow(color: const Color(0xFF90A17D).withOpacity(0.4), blurRadius: 5, offset: const Offset(0, 2))]
            : [],
      ),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              category,
              style: TextStyle(
                 color: isSelected ? Colors.white : Colors.black54,
                 fontWeight: FontWeight.bold,
              ),
            ),
            if (badge != null && badge > 0) ...[
              const SizedBox(width: 6),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: isSelected 
                    ? Colors.white.withOpacity(0.3) 
                    : const Color(0xFF90A17D),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    badge.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
}
