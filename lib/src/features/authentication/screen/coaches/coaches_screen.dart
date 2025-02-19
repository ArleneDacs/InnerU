import 'package:flutter/material.dart';

class Coach {
  final String name;

  Coach({required this.name});
}

class CoachesScreen extends StatefulWidget {
  const CoachesScreen({super.key});

  @override
  State<CoachesScreen> createState() => _CoachesScreenState();
}

class _CoachesScreenState extends State<CoachesScreen> {
  final List<Coach> coaches = [
    Coach(name: 'John Angel Bahaynon'),
    Coach(name: 'Trixie Nicole Rosales'),
    Coach(name: 'Craig Euwan De Culano'),
    Coach(name: 'Arlene Mae Dacanay'),
  ];
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Coach> get filteredCoaches {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      return coaches;
    }
    return coaches.where((coach) {
      return coach.name.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text(
                    'Our Coaches',
                    style: TextStyle(
                      fontSize: 24,
                    ),
                  ),
                ],
              ),
            ),

            // Illustration
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 20.0),
                child: SizedBox(
                  height: 280,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Image.asset(
                      'assets/images/coachpic.png',
                      width: 400,
                      height: 300,
                    ),
                  ),
                )),

            // Search Bar
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search',
                  filled: true,
                  fillColor: Colors.grey.shade200,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
            ),

            // Coaches List
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16.0),
                itemCount: filteredCoaches.length,
                itemBuilder: (context, index) {
                  final coach = filteredCoaches[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8.0),
                    decoration: BoxDecoration(
                      color: index.isEven
                          ? const Color(0xFF90A17D)
                          : const Color(0xFF6D849A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.white,
                        child: Icon(Icons.person, color: Colors.grey),
                      ),
                      title: Text(
                        coach.name,
                        style: const TextStyle(
                          color: Colors
                              .white, // Changed from Colors.black87 to Colors.white
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => AddCoachDialog(
              onCoachAdded: (coach) {
                setState(() {
                  coaches.add(coach);
                });
              },
            ),
          );
        },
        backgroundColor: const Color(0xFFEFD199),
        shape: const CircleBorder(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class AddCoachDialog extends StatefulWidget {
  final Function(Coach) onCoachAdded;

  const AddCoachDialog({
    super.key,
    required this.onCoachAdded,
  });

  @override
  State<AddCoachDialog> createState() => _AddCoachDialogState();
}

class _AddCoachDialogState extends State<AddCoachDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isMale = true;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Add a Coach',
                  style: TextStyle(
                    fontSize: 20,
                    fontFamily: 'serif',
                    fontStyle: FontStyle.italic,
                  ),
                ),
                Image.asset(
                  'assets/images/star1.png',
                  width: 25,
                  height: 25,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Full Name
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: 'Full Name',
                filled: true,
                fillColor: Colors.grey[200],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Description
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Description',
                filled: true,
                fillColor: Colors.grey[200],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Gender Toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Male'),
                Switch(
                  value: _isMale,
                  onChanged: (value) => setState(() => _isMale = value),
                  activeColor: const Color(0xFF90A17D),
                ),
                const Text('Female'),
              ],
            ),
            const SizedBox(height: 20),

            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () {
                    if (_nameController.text.isNotEmpty) {
                      widget.onCoachAdded(Coach(
                        name: _nameController.text,
                      ));
                      Navigator.of(context).pop();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 255, 255, 255),
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                  ),
                  child: const Text(
                    'ADD',
                    style: TextStyle(color: Color(0xFFCE8F5A)),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFCE8F5A),
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                  ),
                  child: const Text(
                    'CANCEL',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
