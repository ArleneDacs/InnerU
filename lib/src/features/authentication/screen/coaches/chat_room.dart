import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/features/authentication/screen/coaches/coaches_screen.dart';

class Message {
  Message({
    required this.senderId,
    required this.senderName,
    required this.message,
    required this.timestamp,
  });

  final String senderId;
  final String senderName;
  final String message;
  final DateTime timestamp;

  factory Message.fromDocument(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final serverTimestamp = data['timestamp'];
    final clientTimestamp = data['clientTimestamp'];

    DateTime resolvedTime = DateTime.now();
    if (serverTimestamp is Timestamp) {
      resolvedTime = serverTimestamp.toDate();
    } else if (clientTimestamp is Timestamp) {
      resolvedTime = clientTimestamp.toDate();
    }

    return Message(
      senderId: data['senderId'] as String? ?? '',
      senderName: data['senderName'] as String? ?? '',
      message: data['message'] as String? ?? '',
      timestamp: resolvedTime,
    );
  }
}

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({
    super.key,
    required this.coach,
    required this.userId,
    required this.userName,
  });

  final Coach coach;
  final String userId;
  final String userName;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;

  String getChatRoomId() {
    final sortedIds = [widget.coach.id, widget.userId]..sort();
    return '${sortedIds[0]}_${sortedIds[1]}';
  }

  Future<void> _sendMessage() async {
    final trimmedMessage = _messageController.text.trim();
    if (trimmedMessage.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    final chatRoomId = getChatRoomId();
    final now = DateTime.now();
    final roomRef =
        FirebaseFirestore.instance.collection('chatRooms').doc(chatRoomId);
    final messageRef = roomRef.collection('messages').doc();

    try {
      final batch = FirebaseFirestore.instance.batch();

      batch.set(messageRef, {
        'senderId': widget.userId,
        'senderName': widget.userName,
        'message': trimmedMessage,
        'timestamp': FieldValue.serverTimestamp(),
        'clientTimestamp': Timestamp.fromDate(now),
      });

      batch.set(roomRef, {
        'chatRoomId': chatRoomId,
        'lastMessage': trimmedMessage,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastSenderId': widget.userId,
        'participants': [widget.userId, widget.coach.id],
        'participantNames': {
          widget.userId: widget.userName,
          widget.coach.id: widget.coach.name,
        },
        'coachId': widget.coach.id,
        'coachName': widget.coach.name,
        'userId': widget.userId,
        'userName': widget.userName,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();
      _messageController.clear();
      _scrollToBottom(animated: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _scrollToBottom({bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          position,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(position);
      }
    });
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
    final accentColor = widget.coach.backgroundColor;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: accentColor,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.arrow_left, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white,
              backgroundImage: widget.coach.profilePic.trim().isNotEmpty
                  ? NetworkImage(widget.coach.profilePic)
                  : null,
              child: widget.coach.profilePic.trim().isEmpty
                  ? const Icon(Icons.person, color: Colors.grey)
                  : null,
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                widget.coach.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                image: const DecorationImage(
                  image: AssetImage('assets/images/star1.png'),
                  opacity: 0.05,
                  repeat: ImageRepeat.repeat,
                ),
              ),
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
                  _scrollToBottom();

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isMe = message.senderId == widget.userId;
                      final previousDate = index > 0
                          ? messages[index - 1].timestamp
                          : DateTime(2000);
                      final showDateSeparator =
                          !_isSameDay(message.timestamp, previousDate);
                      final previousSender =
                          index > 0 ? messages[index - 1].senderId : '';
                      final showSenderName =
                          previousSender != message.senderId || showDateSeparator;

                      return Column(
                        children: [
                          if (showDateSeparator)
                            _buildDateSeparator(message.timestamp),
                          if (showSenderName)
                            _buildSenderHeader(message.senderName),
                          _buildMessageBubble(
                            message: message,
                            isMe: isMe,
                            accentColor: accentColor,
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
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
      padding: const EdgeInsets.only(top: 16, bottom: 8),
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
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey.shade400)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
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
    }
    return DateFormat('MMM d, yyyy').format(date);
  }

  Widget _buildMessageBubble({
    required Message message,
    required bool isMe,
    required Color accentColor,
  }) {
    final time = DateFormat('h:mm a').format(message.timestamp);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
                color: isMe ? accentColor : Colors.white,
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
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        message.senderName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.grey.shade700,
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

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  final String userId;
  final String userName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Messages'),
        backgroundColor: const Color(0xFF90A17D),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
              final chatDoc = snapshot.data!.docs[index];
              final chatData = chatDoc.data();
              final participants =
                  List<String>.from(chatData['participants'] as List? ?? []);
              final participantNames = Map<String, dynamic>.from(
                chatData['participantNames'] as Map? ?? {},
              );
              final otherParticipantId = participants.firstWhere(
                (participantId) => participantId != userId,
                orElse: () => chatData['coachId'] as String? ?? '',
              );
              final otherName =
                  participantNames[otherParticipantId] as String? ??
                      (chatData['coachId'] == userId
                          ? chatData['userName'] as String? ?? 'User'
                          : chatData['coachName'] as String? ?? 'Coach');
              final lastMessage = chatData['lastMessage'] as String? ?? '';
              final lastMessageStamp = chatData['lastMessageTime'];
              final lastMessageTime = lastMessageStamp is Timestamp
                  ? lastMessageStamp.toDate()
                  : DateTime.now();

              final peer = Coach(
                id: otherParticipantId,
                name: otherName,
                bio: '',
                profilePic: '',
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
                        coach: peer,
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
    }
    return DateFormat('MM/dd/yy').format(dateTime);
  }
}
