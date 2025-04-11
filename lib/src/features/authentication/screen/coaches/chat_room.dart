import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'coaches_screen.dart';

// Add this class to your existing code
class Message {
  final String senderId;
  final String senderName;
  final String message;
  final DateTime timestamp;

  Message({
    required this.senderId,
    required this.senderName,
    required this.message,
    required this.timestamp,
  });

  // Convert to a map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'message': message,
      'timestamp': timestamp,
    };
  }

  // Create a Message from a Firestore document
  factory Message.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Message(
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? '',
      message: data['message'] ?? '',
      timestamp: (data['timestamp'] as Timestamp).toDate(),
    );
  }
}

// Add this class to implement the chat room screen
class ChatRoomScreen extends StatefulWidget {
  final Coach coach;
  final String userId; // Current user ID
  final String userName; // Current user name

  const ChatRoomScreen({
    super.key,
    required this.coach,
    required this.userId,
    required this.userName,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Get chat room ID (a combination of coach ID and user ID)
  String getChatRoomId() {
    // This assumes coach has an ID. If not, you'll need to modify this
    // For now, we'll use coach name as a simple placeholder
    final coachId = widget.coach.name.replaceAll(' ', '_').toLowerCase();
    final userId = widget.userId;

    // Sort to ensure the same chat room ID regardless of who initiates
    final sortedIds = [coachId, userId]..sort();
    return '${sortedIds[0]}_${sortedIds[1]}';
  }

  // Send a message
  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final chatRoomId = getChatRoomId();
    final message = Message(
      senderId: widget.userId,
      senderName: widget.userName,
      message: _messageController.text.trim(),
      timestamp: DateTime.now(),
    );

    try {
      // Add message to the chat room collection
      await FirebaseFirestore.instance
          .collection('chatRooms')
          .doc(chatRoomId)
          .collection('messages')
          .add(message.toMap());

      // Update chat room metadata
      await FirebaseFirestore.instance
          .collection('chatRooms')
          .doc(chatRoomId)
          .set({
        'lastMessage': message.message,
        'lastMessageTime': message.timestamp,
        'participants': [
          widget.userId,
          widget.coach.name.replaceAll(' ', '_').toLowerCase()
        ],
        'coachName': widget.coach.name,
        'userName': widget.userName,
      });

      // Clear the text field
      _messageController.clear();

      // Scroll to the bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      // Show error if message fails to send
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message: $e')),
      );
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatRoomId = getChatRoomId();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: widget.coach.backgroundColor,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.arrow_left, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.person, color: Colors.grey),
            ),
            const SizedBox(width: 12),
            Text(
              widget.coach.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Chat messages area
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                image: DecorationImage(
                  image: AssetImage('assets/images/star1.png'),
                  opacity: 0.05,
                  repeat: ImageRepeat.repeat,
                ),
              ),
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('chatRooms')
                    .doc(chatRoomId)
                    .collection('messages')
                    .orderBy('timestamp', descending: false)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/images/star1.png',
                            width: 80,
                            height: 80,
                            opacity: const AlwaysStoppedAnimation(0.6),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Start a conversation with ${widget.coach.name}',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final messages = snapshot.data!.docs
                      .map((doc) => Message.fromDocument(doc))
                      .toList();

                  return ListView.builder(
  controller: _scrollController,
  padding: const EdgeInsets.all(16),
  itemCount: messages.length,
  itemBuilder: (context, index) {
    final message = messages[index];
    final isMe = message.senderId == widget.userId;
    
    // Check if this is a date separator
    final previousDate = index > 0
        ? messages[index - 1].timestamp
        : DateTime(2000);
    final showDateSeparator = !_isSameDay(message.timestamp, previousDate);
    
    // Check if this is a new sender
    final previousSender = index > 0 ? messages[index - 1].senderId : "";
    final showSenderName = previousSender != message.senderId || showDateSeparator;
    
    return Column(
      children: [
        // Show date separator if needed
        if (showDateSeparator)
          _buildDateSeparator(message.timestamp),
        
        // Show sender name if it's a new sender or after date separator
        if (showSenderName)
          _buildSenderHeader(message.senderName),
          
        _buildMessageBubble(message, isMe),
      ],
    );
  },
);
                },
              ),
            ),
          ),

          // Message input area
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Message',
                      filled: true,
                      fillColor: Colors.grey.shade200,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFD199),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(
                      CupertinoIcons.arrow_right,
                      color: Colors.white,
                    ),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  Widget _buildSenderHeader(String senderName) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
    child: Text(
      senderName,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 16,
        color: Colors.grey.shade800,
      ),
      textAlign: TextAlign.center,
    ),
  );
}

  Widget _buildDateSeparator(DateTime date) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 16.0),
    child: Row(
      children: [
        Expanded(child: Divider(color: Colors.grey.shade400)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Text(
            _getDateText(date),
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.grey.shade400)),
      ],
    ),
  );
}

  String _getDateText(DateTime date) {
    final now = DateTime.now();
    if (_isSameDay(date, now)) {
      return 'Today';
    } else if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    } else {
      return DateFormat('MMM d, yyyy').format(date);
    }
  }

  Widget _buildMessageBubble(Message message, bool isMe) {
    final time = DateFormat('h:mm a').format(message.timestamp);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            const CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white,
              child: Icon(Icons.person, size: 20, color: Colors.grey),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? widget.coach.backgroundColor : Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Text(
                        message.senderName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: isMe ? Colors.white70 : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  Text(
                    message.message,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      time,
                      style: TextStyle(
                        fontSize: 10,
                        color: isMe ? Colors.white70 : Colors.grey.shade500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

// Modify the existing CoachProfileDialog to open the ChatRoomScreen
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
                  icon: const Icon(
                    CupertinoIcons.chat_bubble_2_fill,
                    size: 30,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    // Close the profile dialog
                    Navigator.pop(context);

                    // Open the chat room
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatRoomScreen(
                          coach: coach,
                          userId: 'user_123',
                          userName:
                              'Current User', 
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
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

// Add this class to implement a chat list screen (optional, for future use)
class ChatListScreen extends StatelessWidget {
  final String userId;
  final String userName;

  const ChatListScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Messages'),
        backgroundColor: const Color(0xFF90A17D),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chatRooms')
            .where('participants', arrayContains: userId)
            .orderBy('lastMessageTime', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/star1.png',
                    width: 80,
                    height: 80,
                    opacity: const AlwaysStoppedAnimation(0.6),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No conversations yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final chatData =
                  snapshot.data!.docs[index].data() as Map<String, dynamic>;
              final chatId = snapshot.data!.docs[index].id;
              final otherName = chatData['coachName'] ?? 'Coach';
              final lastMessage = chatData['lastMessage'] ?? '';
              final lastMessageTime =
                  (chatData['lastMessageTime'] as Timestamp).toDate();

              // Find the coach from your existing coaches list (you'll need to modify this)
              // For simplicity, we'll create a dummy coach
              final coach = Coach(
                name: otherName,
                bio: '',
                backgroundColor: const Color(0xFF90A17D),
              );

              return ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF90A17D),
                  child: Icon(Icons.person, color: Colors.white),
                ),
                title: Text(otherName),
                subtitle: Text(
                  lastMessage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  _formatChatTime(lastMessageTime),
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChatRoomScreen(
                        coach: coach,
                        userId: userId,
                        userName: userName,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  String _formatChatTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateToCheck = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (dateToCheck == today) {
      return DateFormat('h:mm a').format(dateTime);
    } else if (dateToCheck == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('MM/dd/yy').format(dateTime);
    }
  }
}
