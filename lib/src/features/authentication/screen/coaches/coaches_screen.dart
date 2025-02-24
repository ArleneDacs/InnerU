import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class Coach {
  final String name;
  final String bio;
  final Color backgroundColor;
  
  Coach({
    required this.name,
    this.bio = '',
    required this.backgroundColor,
  });
}

class CoachProfileDialog extends StatelessWidget {
  final Coach coach;

  const CoachProfileDialog({
    super.key,
    required this.coach,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: coach.backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with back and message icons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(
                    CupertinoIcons.arrow_left,
                    color: Colors.white,
                  ),
                 onPressed: () => Navigator.pop(context),
                ),
                IconButton(
                  icon: Icon(CupertinoIcons.chat_bubble_2_fill, size: 30, color: Colors.white,),
                  onPressed: () {
                    // Implement messaging functionality
                  },
                ),
              ],
            ),

            // Profile picture
            const CircleAvatar(
              radius: 50,
              backgroundColor: Colors.white,
              child: Icon(
                Icons.person,
                size: 50,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),

            // Name
            Text(
              coach.name,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Bio section
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Bio:',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                coach.bio.isEmpty ? 'No bio available' : coach.bio,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CoachesScreen extends StatefulWidget {
  const CoachesScreen({super.key});

  @override
  State<CoachesScreen> createState() => _CoachesScreenState();
}

class _CoachesScreenState extends State<CoachesScreen> {
  static const Color evenColor = Color(0xFF90A17D); // Green color
  static const Color oddColor = Color(0xFF6D849A);  // Blue color

  final List<Coach> coaches = [
    Coach(
      name: 'John Angel Bahaynon',
      bio: 'Firm believer. Life coach.',
      backgroundColor: evenColor,
    ),
    Coach(
      name: 'Trixie Nicole Rosales',
      bio: '',
      backgroundColor: oddColor,
    ),
    Coach(
      name: 'Craig Euwan De Culano',
      bio: '',
      backgroundColor: evenColor,
    ),
    Coach(
      name: 'Arlene Mae Dacanay',
      bio: '',
      backgroundColor: oddColor,
    ),
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
                    icon: Icon(CupertinoIcons.arrow_left),
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
              ),
            ),

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

            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16.0),
                itemCount: filteredCoaches.length,
                itemBuilder: (context, index) {
                  final coach = filteredCoaches[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8.0),
                    decoration: BoxDecoration(
                      color: coach.backgroundColor,
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
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) => CoachProfileDialog(coach: coach),
                        );
                      },
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
              currentCoachCount: coaches.length,
            ),
          );
        },
        backgroundColor: const Color(0xFFEFD199),
        shape: const CircleBorder(),
        child: const Icon(CupertinoIcons.add, size: 30, color: Colors.white),
      ),
    );
  }
}

// Adding the Coaches

class AddCoachDialog extends StatefulWidget {
  final Function(Coach) onCoachAdded;
  final int currentCoachCount;

  const AddCoachDialog({
    super.key,
    required this.onCoachAdded,
    required this.currentCoachCount,
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
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: 'Full Name',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Bio Description',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () {
                    if (_nameController.text.isNotEmpty) {
                      final isEven = widget.currentCoachCount.isEven;
                      widget.onCoachAdded(Coach(
                        name: _nameController.text,
                        bio: _descriptionController.text,
                        backgroundColor: isEven ? 
                          const Color(0xFF90A17D) : 
                          const Color(0xFF6D849A),
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