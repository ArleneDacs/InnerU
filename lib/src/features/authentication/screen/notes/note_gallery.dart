// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter/material.dart';
// import 'package:selfcare_projects/src/features/authentication/screen/UsersData/UserService.dart';
// import 'package:selfcare_projects/src/features/authentication/screen/notes/note_card.dart';
// import 'package:selfcare_projects/src/features/authentication/screen/notes/notes_type.dart';
// import 'package:selfcare_projects/src/models/note_model.dart';

// class NotesGallery extends StatefulWidget {
//   const NotesGallery({super.key});

//   @override
//   State<NotesGallery> createState() => _NotesGallery();
// }

// class _NotesGallery extends State<NotesGallery> {
//   final CollectionReference myNotes =
//       FirebaseFirestore.instance.collection('notes');
//   String username = "Loading...";

//   @override
//   void initState() {
//     // TODO: implement initState
//     super.initState();
//     UserService.getUserData().then((data) => setState(() {
//           username = data["username"]!;
//         }));
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text("Journal"),
//         leading: IconButton(
//             onPressed: () {
//               Navigator.pop(context);
//             },
//             icon: Icon(Icons.arrow_back)),
//         actions: [IconButton(onPressed: () {}, icon: Icon(Icons.menu))],
//       ),
//       body: Column(
//         children: [
//           Flexible(
//             child: StreamBuilder(
//               stream: myNotes.snapshots(),
//               builder: (context, snapshot) {
//                 if (!snapshot.hasData) {
//                   return Center(child: CircularProgressIndicator());
//                 }
//                 final notes = snapshot.data!.docs;
//                 List<NoteCard> noteCards = [];
//                 for (var note in notes) {
//                   var data = note.data() as Map<String, dynamic>?;
//                   if (data != null && data['username'] == username) {
//                     Note noteObject = Note(
//                       id: note.id,
//                       username: data['username'] ?? "",
//                       title: data['title'] ?? "",
//                       note: data['note'] ?? "",
//                       createdAt: data.containsKey('createdAt')
//                           ? (data['createdAt'] as Timestamp).toDate()
//                           : DateTime.now(),
//                       updatedAt: data.containsKey('updatedAt')
//                           ? (data['updatedAt'] as Timestamp).toDate()
//                           : DateTime.now(),
//                       color: data.containsKey('color')
//                           ? data['color']
//                           : 0xFFFFFFFF,
//                     );
//                     noteCards.add(
//                       NoteCard(
//                         note: noteObject,
//                         onPressed: () {
//                           Navigator.push(
//                             context,
//                             MaterialPageRoute(
//                               builder: (context) => NotesType(note: noteObject),
//                             ),
//                           );
//                         },
//                       ),
//                     );
//                   }
//                 }
//                 return GridView.builder(
//                   gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
//                     crossAxisCount: 2,
//                     crossAxisSpacing: 10,
//                     mainAxisSpacing: 10,
//                   ),
//                   itemCount: noteCards.length,
//                   itemBuilder: (context, index) {
//                     return noteCards[index];
//                   },
//                   padding: EdgeInsets.all(3),
//                 );
//               },
//             ),
//           ),
//         ],
//       ),
//       floatingActionButton: FloatingActionButton(
//         onPressed: () {
//           Navigator.pushNamed(context, 'notesType');
//         },
//         backgroundColor: Color(0xff5EC0CA),
//         child: Icon(
//           Icons.add,
//           color: Colors.white,
//         ),
//       ),
//     );
//   }
// }
