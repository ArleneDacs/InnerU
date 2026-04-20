import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/features/authentication/screen/coaches/coaches_screen.dart';
import 'package:selfcare_projects/src/services/image_storage_service.dart';

class Message {
  Message({
    required this.senderId,
    required this.senderName,
    required this.message,
    required this.timestamp,
    this.senderProfilePic,
    this.imageUrl,
  });

  final String senderId;
  final String senderName;
  final String message;
  final DateTime timestamp;
  final String? senderProfilePic;
  final String? imageUrl;

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
      senderProfilePic: (data['senderProfilePic'] as String?)?.trim(),
      imageUrl: (data['imageUrl'] as String?)?.trim(),
    );
  }
}

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({
    super.key,
    required this.coach,
    required this.userId,
    required this.userName,
    this.chatRoomId,
    this.chatTitle,
    this.chatProfilePic,
    this.isGroupChat = false,
  });

  final Coach coach;
  final String userId;
  final String userName;
  final String? chatRoomId;
  final String? chatTitle;
  final String? chatProfilePic;
  final bool isGroupChat;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isSending = false;
  bool _isUploadingImage = false;
  String? _currentUserProfilePic;

  @override
  void initState() {
    super.initState();
    _markChatAsRead();
    _loadCurrentUserProfilePic();
  }

  String getChatRoomId() {
    if ((widget.chatRoomId ?? '').trim().isNotEmpty) {
      return widget.chatRoomId!.trim();
    }
    final sortedIds = [widget.coach.id, widget.userId]..sort();
    return '${sortedIds[0]}_${sortedIds[1]}';
  }

  String get _chatTitle {
    final provided = (widget.chatTitle ?? '').trim();
    if (provided.isNotEmpty) return provided;
    return widget.coach.name;
  }

  String get _chatProfilePic {
    final provided = (widget.chatProfilePic ?? '').trim();
    if (provided.isNotEmpty) return provided;
    return widget.coach.profilePic.trim();
  }

  Future<void> _markChatAsRead() async {
    try {
      final now = Timestamp.now();
      await FirebaseFirestore.instance
          .collection('chatRooms')
          .doc(getChatRoomId())
          .set({
        'unreadCounts.${widget.userId}': 0,
        'lastReadAt.${widget.userId}': now,
        'updatedAt': now,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<String?> _fetchProfilePicForUser(String uid) async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final userPic = (userDoc.data()?['profilePic'] as String?)?.trim();
      if (userPic != null && userPic.isNotEmpty) {
        return userPic;
      }

      final coachDoc =
          await FirebaseFirestore.instance.collection('coaches').doc(uid).get();
      final coachPic = (coachDoc.data()?['profilePic'] as String?)?.trim();
      if (coachPic != null && coachPic.isNotEmpty) {
        return coachPic;
      }
    } catch (_) {}

    return null;
  }

  Future<void> _loadCurrentUserProfilePic() async {
    final profilePic = await _fetchProfilePicForUser(widget.userId);
    if (!mounted) return;
    setState(() {
      _currentUserProfilePic = profilePic;
    });
  }

  Future<void> _sendMessage({String? imageUrl}) async {
    final trimmedMessage = _messageController.text.trim();
    if ((trimmedMessage.isEmpty && (imageUrl ?? '').trim().isEmpty) || _isSending) {
      return;
    }

    setState(() => _isSending = true);
    final chatRoomId = getChatRoomId();
    final now = DateTime.now();
    final roomRef =
        FirebaseFirestore.instance.collection('chatRooms').doc(chatRoomId);
    final messageRef = roomRef.collection('messages').doc();

    try {
      final batch = FirebaseFirestore.instance.batch();
      final roomSnapshot = await roomRef.get();
      final roomData = roomSnapshot.data() ?? <String, dynamic>{};
      final participants = List<String>.from(
        roomData['participants'] as List? ??
            (widget.isGroupChat
                ? <String>[widget.userId]
                : <String>[widget.userId, widget.coach.id]),
      );
      final participantNames = Map<String, dynamic>.from(
        roomData['participantNames'] as Map? ?? <String, dynamic>{},
      );
      final participantProfiles = Map<String, dynamic>.from(
        roomData['participantProfiles'] as Map? ?? <String, dynamic>{},
      );

      if (!participants.contains(widget.userId)) {
        participants.add(widget.userId);
      }
      if (!widget.isGroupChat && !participants.contains(widget.coach.id)) {
        participants.add(widget.coach.id);
      }

      participantNames[widget.userId] = widget.userName;
      participantProfiles[widget.userId] = _currentUserProfilePic ?? '';
      if (!widget.isGroupChat) {
        participantNames[widget.coach.id] = widget.coach.name;
        participantProfiles[widget.coach.id] = widget.coach.profilePic.trim();
      }

      final roomPayload = <String, dynamic>{
        'chatRoomId': chatRoomId,
        'lastMessage': trimmedMessage.isNotEmpty
            ? trimmedMessage
            : ((imageUrl ?? '').isNotEmpty ? 'Sent a photo' : ''),
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastSenderId': widget.userId,
        'participants': participants,
        'participantNames': participantNames,
        'participantProfiles': participantProfiles,
        'coachId': widget.coach.id,
        'coachName': widget.coach.name,
        'userId': widget.userId,
        'userName': widget.userName,
        'lastReadAt.${widget.userId}': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (widget.isGroupChat) {
        roomPayload['isGroupChat'] = true;
        roomPayload['groupName'] = _chatTitle;
        roomPayload['groupProfilePic'] = _chatProfilePic;
      } else {
        roomPayload['unreadCounts.${widget.userId}'] = 0;
        roomPayload['unreadCounts.${widget.coach.id}'] = FieldValue.increment(1);
      }

      for (final participantId in participants) {
        if (participantId == widget.userId) {
          roomPayload['unreadCounts.$participantId'] = 0;
        } else {
          roomPayload['unreadCounts.$participantId'] = FieldValue.increment(1);
        }
      }

      batch.set(messageRef, {
        'senderId': widget.userId,
        'senderName': widget.userName,
        'message': trimmedMessage,
        'imageUrl': imageUrl ?? '',
        'senderProfilePic': _currentUserProfilePic ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'clientTimestamp': Timestamp.fromDate(now),
      });

      batch.set(roomRef, roomPayload, SetOptions(merge: true));

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

  Future<void> _pickAndSendImage() async {
    if (_isUploadingImage) return;

    try {
      final pickedFile = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null) return;

      setState(() => _isUploadingImage = true);
      final bytes = await pickedFile.readAsBytes();
      final imageUrl = await ImageStorageService.uploadImageBytes(
        bytes,
        fileName: pickedFile.name,
      );

      if (imageUrl == null || imageUrl.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload image.')),
        );
        return;
      }

      await _sendMessage(imageUrl: imageUrl);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send image: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploadingImage = false);
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
              backgroundImage:
                  _chatProfilePic.isNotEmpty ? NetworkImage(_chatProfilePic) : null,
              child: _chatProfilePic.isEmpty
                  ? Icon(
                      widget.isGroupChat ? Icons.groups : Icons.person,
                      color: Colors.grey,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                _chatTitle,
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
          if (widget.isGroupChat)
            _buildGroupMembersBanner(chatRoomId),
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
                    .orderBy('clientTimestamp', descending: false)
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
                            'Start a conversation with $_chatTitle',
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
                  _markChatAsRead();
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
                IconButton(
                  onPressed: _isUploadingImage ? null : _pickAndSendImage,
                  icon: _isUploadingImage
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(CupertinoIcons.photo),
                ),
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
    final imageUrl = (message.imageUrl ?? '').trim();
    final hasImage = imageUrl.isNotEmpty;
    final profilePic = (message.senderProfilePic ?? '').trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white,
              backgroundImage: profilePic.isNotEmpty ? NetworkImage(profilePic) : null,
              child: profilePic.isEmpty
                  ? const Icon(Icons.person, size: 20, color: Colors.grey)
                  : null,
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
                  if (hasImage)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: message.message.trim().isNotEmpty ? 8 : 0,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          imageUrl,
                          width: 220,
                          height: 220,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 220,
                              height: 220,
                              color: Colors.black12,
                              alignment: Alignment.center,
                              child: const Icon(Icons.broken_image_outlined),
                            );
                          },
                        ),
                      ),
                    ),
                  if (message.message.trim().isNotEmpty)
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

  Widget _buildGroupMembersBanner(String chatRoomId) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('chatRooms')
          .doc(chatRoomId)
          .snapshots(),
      builder: (context, snapshot) {
        final chatData = snapshot.data?.data() ?? <String, dynamic>{};
        final participantNames = Map<String, dynamic>.from(
          chatData['participantNames'] as Map? ?? <String, dynamic>{},
        );
        final participantProfiles = Map<String, dynamic>.from(
          chatData['participantProfiles'] as Map? ?? <String, dynamic>{},
        );
        final participants = List<String>.from(
          chatData['participants'] as List? ?? <String>[],
        );

        if (participants.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Members (${participants.length})',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 58,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: participants.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final participantId = participants[index];
                    final profilePic =
                        (participantProfiles[participantId] as String?)?.trim() ?? '';
                    final name = (participantNames[participantId] as String?)?.trim().isNotEmpty ==
                            true
                        ? (participantNames[participantId] as String).trim()
                        : 'Member';

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F7F2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.white,
                            backgroundImage:
                                profilePic.isNotEmpty ? NetworkImage(profilePic) : null,
                            child: profilePic.isEmpty
                                ? const Icon(Icons.person, size: 18, color: Colors.grey)
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.allowGroupChat = false,
    this.groupName,
  });

  final String userId;
  final String userName;
  final bool allowGroupChat;
  final String? groupName;

  DateTime? _readTimestampForUser(Map<String, dynamic> chatData) {
    final lastReadAt = Map<String, dynamic>.from(
      chatData['lastReadAt'] as Map? ?? <String, dynamic>{},
    );
    final rawValue = lastReadAt[userId];
    if (rawValue is Timestamp) return rawValue.toDate();
    return null;
  }

  int _extractUnreadCount(Map<String, dynamic> chatData) {
    final unreadCounts = Map<String, dynamic>.from(
      chatData['unreadCounts'] as Map? ?? <String, dynamic>{},
    );
    if (unreadCounts.containsKey(userId)) {
      final rawValue = unreadCounts[userId];
      if (rawValue is int) return rawValue;
      if (rawValue is num) return rawValue.toInt();
    }
    final lastSenderId = (chatData['lastSenderId'] as String?)?.trim() ?? '';
    final lastMessageTime = _resolveChatSortTime(chatData);
    final lastReadAt = _readTimestampForUser(chatData);
    if (lastSenderId.isNotEmpty &&
        lastSenderId != userId &&
        (lastReadAt == null || lastMessageTime.isAfter(lastReadAt))) {
      return 1;
    }
    return 0;
  }

  DateTime _resolveChatSortTime(Map<String, dynamic> chatData) {
    final lastMessageTime = chatData['lastMessageTime'];
    if (lastMessageTime is Timestamp) {
      return lastMessageTime.toDate();
    }

    final updatedAt = chatData['updatedAt'];
    if (updatedAt is Timestamp) {
      return updatedAt.toDate();
    }

    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _resolvePeerProfilePic(
    Map<String, dynamic> chatData,
    String participantId,
  ) {
    final participantProfiles = Map<String, dynamic>.from(
      chatData['participantProfiles'] as Map? ?? <String, dynamic>{},
    );
    return (participantProfiles[participantId] as String?)?.trim() ??
        (chatData['groupProfilePic'] as String?)?.trim() ??
        '';
  }

  Future<void> _markAllChatsAsRead(BuildContext context) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final now = Timestamp.now();
      final roomsSnapshot = await firestore
          .collection('chatRooms')
          .where('participants', arrayContains: userId)
          .get();

      if (roomsSnapshot.docs.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No messages to mark as read.')),
        );
        return;
      }

      final batch = firestore.batch();
      for (final room in roomsSnapshot.docs) {
        batch.set(room.reference, {
          'unreadCounts.$userId': 0,
          'lastReadAt.$userId': now,
        }, SetOptions(merge: true));
      }

      await batch.commit();

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All messages marked as read.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to mark messages as read: $e')),
      );
    }
  }

  Future<void> _markChatAsReadById(String chatRoomId) async {
    final now = Timestamp.now();
    await FirebaseFirestore.instance.collection('chatRooms').doc(chatRoomId).set({
      'unreadCounts.$userId': 0,
      'lastReadAt.$userId': now,
    }, SetOptions(merge: true));
  }

  Future<void> _createOrOpenGroupChat(BuildContext context) async {
    final firestore = FirebaseFirestore.instance;
    final menteesSnapshot = await firestore
        .collection('users')
        .where('coachId', isEqualTo: userId)
        .get();

    if (menteesSnapshot.docs.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add mentees first to create a group chat.')),
      );
      return;
    }

    final coachDoc = await firestore.collection('coaches').doc(userId).get();
    final userDoc = await firestore.collection('users').doc(userId).get();
    final coachData = coachDoc.data() ?? <String, dynamic>{};
    final userData = userDoc.data() ?? <String, dynamic>{};
    final teamTitle = (groupName ?? '').trim().isNotEmpty
        ? groupName!.trim()
        : ((coachData['fullName'] as String?)?.trim().isNotEmpty == true
              ? (coachData['fullName'] as String).trim()
              : 'My Team');
    final coachProfilePic =
        (coachData['profilePic'] as String?)?.trim().isNotEmpty == true
            ? (coachData['profilePic'] as String).trim()
            : (userData['profilePic'] as String?)?.trim() ?? '';

    final participantIds = <String>{userId};
    final participantNames = <String, String>{userId: userName};
    final participantProfiles = <String, String>{userId: coachProfilePic};

    for (final mentee in menteesSnapshot.docs) {
      final data = mentee.data();
      participantIds.add(mentee.id);
      participantNames[mentee.id] =
          (data['username'] as String?)?.trim().isNotEmpty == true
              ? (data['username'] as String).trim()
              : 'Mentee';
      participantProfiles[mentee.id] = (data['profilePic'] as String?)?.trim() ?? '';
    }

    final chatRoomId = 'group_$userId';
    final unreadCounts = <String, int>{};
    for (final participantId in participantIds) {
      unreadCounts[participantId] = 0;
    }

    await firestore.collection('chatRooms').doc(chatRoomId).set({
      'chatRoomId': chatRoomId,
      'isGroupChat': true,
      'groupName': teamTitle,
      'groupProfilePic': coachProfilePic,
      'participants': participantIds.toList(),
      'participantNames': participantNames,
      'participantProfiles': participantProfiles,
      'unreadCounts': unreadCounts,
      'coachId': userId,
      'coachName': teamTitle,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatRoomScreen(
          coach: Coach(
            id: userId,
            name: teamTitle,
            profilePic: coachProfilePic,
            backgroundColor: const Color(0xFF90A17D),
          ),
          userId: userId,
          userName: userName,
          chatRoomId: chatRoomId,
          chatTitle: teamTitle,
          chatProfilePic: coachProfilePic,
          isGroupChat: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Messages'),
        backgroundColor: const Color(0xFF90A17D),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Read all',
            onPressed: () => _markAllChatsAsRead(context),
          ),
          if (allowGroupChat)
            IconButton(
              icon: const Icon(Icons.groups_2_outlined),
              onPressed: () => _createOrOpenGroupChat(context),
            ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('chatRooms')
            .where('participants', arrayContains: userId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = [...?snapshot.data?.docs]
            ..sort((a, b) {
              final aTime = _resolveChatSortTime(a.data());
              final bTime = _resolveChatSortTime(b.data());
              return bTime.compareTo(aTime);
            });

          if (docs.isEmpty) {
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
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final chatDoc = docs[index];
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
                  chatData['isGroupChat'] == true
                      ? (chatData['groupName'] as String?)?.trim() ?? 'My Team'
                      : participantNames[otherParticipantId] as String? ??
                          (chatData['coachId'] == userId
                              ? chatData['userName'] as String? ?? 'User'
                              : chatData['coachName'] as String? ?? 'Coach');
              final lastMessage = chatData['lastMessage'] as String? ?? '';
              final lastMessageTime = _resolveChatSortTime(chatData);
              final unreadCount = _extractUnreadCount(chatData);
              final isGroupChat = chatData['isGroupChat'] == true;
              final peerProfilePic = _resolvePeerProfilePic(chatData, otherParticipantId);

              final peer = Coach(
                id: otherParticipantId,
                name: otherName,
                bio: '',
                profilePic: peerProfilePic,
                backgroundColor: const Color(0xFF90A17D),
              );

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF90A17D),
                  backgroundImage:
                      peerProfilePic.isNotEmpty ? NetworkImage(peerProfilePic) : null,
                  child: peerProfilePic.isEmpty
                      ? Icon(
                          isGroupChat ? Icons.groups : Icons.person,
                          color: Colors.white,
                        )
                      : null,
                ),
                title: Text(otherName),
                subtitle: Text(
                  lastMessage.isEmpty && chatData['isGroupChat'] == true
                      ? 'Group chat'
                      : lastMessage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatChatTime(lastMessageTime),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (unreadCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE56B6F),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          unreadCount > 99 ? '99+' : '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                onTap: () {
                  _markChatAsReadById(chatDoc.id).then((_) {
                    if (!context.mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatRoomScreen(
                          coach: peer,
                          userId: userId,
                          userName: userName,
                          chatRoomId: isGroupChat ? chatDoc.id : null,
                          chatTitle: isGroupChat ? otherName : null,
                          chatProfilePic: isGroupChat ? peerProfilePic : null,
                          isGroupChat: isGroupChat,
                        ),
                      ),
                    );
                  });
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
