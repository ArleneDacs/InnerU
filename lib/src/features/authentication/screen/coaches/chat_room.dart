import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/user_service.dart';
import 'package:selfcare_projects/src/features/authentication/screen/coaches/coaches_screen.dart';
import 'package:selfcare_projects/src/services/admin_user_api_service.dart';
import 'package:selfcare_projects/src/services/coach_directory_api_service.dart';
import 'package:selfcare_projects/src/services/chat_api_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/image_storage_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  factory Message.fromJson(Map<String, dynamic> data) {
    return Message(
      senderId: data['senderId'] as String? ?? '',
      senderName: data['senderName'] as String? ?? '',
      message: data['message'] as String? ?? '',
      timestamp: DateTime.tryParse(
            (data['timestamp'] ?? data['clientTimestamp'])?.toString() ?? '',
          ) ??
          DateTime.now(),
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
  final ChatApiService _chatApi = ChatApiService.instance;
  bool _isSending = false;
  bool _isUploadingImage = false;
  String? _currentUserProfilePic;
  String? _resolvedChatRoomId;

  @override
  void initState() {
    super.initState();
    _resolveChatRoomId().then((_) => _markChatAsRead());
    _loadCurrentUserProfilePic();
  }

  String getChatRoomId() {
    if ((widget.chatRoomId ?? '').trim().isNotEmpty) {
      return widget.chatRoomId!.trim();
    }
    if ((_resolvedChatRoomId ?? '').trim().isNotEmpty) {
      return _resolvedChatRoomId!.trim();
    }
    final sortedIds = [widget.coach.id, widget.userId]..sort();
    return '${sortedIds[0]}_${sortedIds[1]}';
  }

  Future<void> _resolveChatRoomId() async {
    if ((widget.chatRoomId ?? '').trim().isNotEmpty || widget.isGroupChat) {
      return;
    }

    try {
      final rooms = await _chatApi.fetchRooms(widget.userId);
      for (final room in rooms) {
        final participants = List<String>.from(
          room['participants'] as List? ?? const <String>[],
        );
        if (room['isGroupChat'] == true) {
          continue;
        }
        if (participants.contains(widget.coach.id)) {
          _resolvedChatRoomId = room['chatRoomId']?.toString();
          return;
        }
      }
    } catch (_) {}
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
      await _chatApi.markRead(getChatRoomId());
    } catch (_) {}
  }

  Future<void> _markChatAsReadUpTo(DateTime timestamp) async {
    try {
      await _chatApi.markRead(getChatRoomId());
    } catch (_) {}
  }

  Future<String?> _fetchProfilePicForUser(String uid) async {
    try {
      if (uid == widget.userId) {
        final userData = await UserService.getUserData();
        final userPic = (userData['profilePic'] as String?)?.trim();
        if (userPic != null && userPic.isNotEmpty) {
          return userPic;
        }
      }

      final coaches = await CoachDirectoryApiService.instance.fetchCoaches();
      for (final coach in coaches) {
        if (coach.id == uid &&
            (coach.profilePic ?? '').trim().isNotEmpty) {
          return coach.profilePic!.trim();
        }
      }

      final users = await AdminUserApiService.instance.fetchUsers();
      for (final user in users) {
        if (user.id == uid && (user.profilePic ?? '').trim().isNotEmpty) {
          return user.profilePic!.trim();
        }
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
    if ((trimmedMessage.isEmpty && (imageUrl ?? '').trim().isEmpty) ||
        _isSending) {
      return;
    }

    setState(() => _isSending = true);
    final chatRoomId = getChatRoomId();
    final now = DateTime.now();

    try {
      final participants = widget.isGroupChat
          ? <String>[widget.userId]
          : <String>[widget.userId, widget.coach.id];
      final participantNames = <String, dynamic>{
        widget.userId: widget.userName,
        if (!widget.isGroupChat) widget.coach.id: widget.coach.name,
      };
      final participantProfiles = <String, dynamic>{
        widget.userId: _currentUserProfilePic ?? '',
        if (!widget.isGroupChat) widget.coach.id: widget.coach.profilePic.trim(),
      };

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
        'id': chatRoomId,
        'is_group_chat': widget.isGroupChat,
        'last_message': trimmedMessage.isNotEmpty
            ? trimmedMessage
            : ((imageUrl ?? '').isNotEmpty ? 'Sent a photo' : ''),
        'last_sender_id': widget.userId,
        'participants': participants,
        'participant_names': participantNames,
        'participant_profiles': participantProfiles,
        'coach_id': widget.coach.id,
        'coach_name': widget.coach.name,
        'user_id': widget.userId,
        'user_name': widget.userName,
        'unread_counts': {
          for (final participantId in participants)
            participantId: participantId == widget.userId ? 0 : 1,
        },
        'last_read_at': {
          widget.userId: now.toIso8601String(),
        },
        'updated_at': now.toIso8601String(),
      };

      if (widget.isGroupChat) {
        roomPayload['group_name'] = _chatTitle;
        roomPayload['group_profile_pic'] = _chatProfilePic;
      } else {
        roomPayload['company_id'] = null;
        roomPayload['company_code'] = null;
        roomPayload['company_name'] = null;
      }

      await _chatApi.saveRoom(roomPayload);
      await _chatApi.sendMessage(chatRoomId, {
        'sender_id': widget.userId,
        'sender_name': widget.userName,
        'message': trimmedMessage,
        'image_url': imageUrl ?? '',
        'sender_profile_pic': _currentUserProfilePic ?? '',
        'client_timestamp': now.toIso8601String(),
      });
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
      final pickedFile =
          await _imagePicker.pickImage(source: ImageSource.gallery);
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
    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        return Theme(
          data: AppTheme.company(companyTheme),
          child: Builder(
            builder: (context) => _buildContent(context, companyTheme),
          ),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, CompanyThemeData companyTheme) {
    final theme = Theme.of(context);
    final accentColor = companyTheme.primaryColor;
    final chatRoomId = getChatRoomId();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.primary,
        leading: IconButton(
          icon: Icon(CupertinoIcons.arrow_left,
              color: theme.colorScheme.onPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.surface,
              backgroundImage: _chatProfilePic.isNotEmpty
                  ? NetworkImage(_chatProfilePic)
                  : null,
              child: _chatProfilePic.isEmpty
                  ? Icon(
                      widget.isGroupChat ? Icons.groups : Icons.person,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                _chatTitle,
                style: TextStyle(
                  color: theme.colorScheme.onPrimary,
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
          if (widget.isGroupChat) _buildGroupMembersBanner(chatRoomId),
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
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _chatApi.watchMessages(chatRoomId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
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

                  final messages = snapshot.data!
                      .map((doc) => Message.fromJson(doc))
                      .toList();
                  final latestReadTimestamp = messages.last.timestamp;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _markChatAsReadUpTo(latestReadTimestamp);
                  });
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
                          previousSender != message.senderId ||
                              showDateSeparator;

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
              backgroundImage:
                  profilePic.isNotEmpty ? NetworkImage(profilePic) : null,
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
                    color: Colors.black.withValues(alpha: 0.05),
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
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _chatApi.watchRoom(chatRoomId),
      builder: (context, snapshot) {
        final chatData = snapshot.data ?? <String, dynamic>{};
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
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final participantId = participants[index];
                    final profilePic =
                        (participantProfiles[participantId] as String?)
                                ?.trim() ??
                            '';
                    final name = (participantNames[participantId] as String?)
                                ?.trim()
                                .isNotEmpty ==
                            true
                        ? (participantNames[participantId] as String).trim()
                        : 'Member';

                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
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
                            backgroundImage: profilePic.isNotEmpty
                                ? NetworkImage(profilePic)
                                : null,
                            child: profilePic.isEmpty
                                ? const Icon(Icons.person,
                                    size: 18, color: Colors.grey)
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

class ChatListScreen extends StatefulWidget {
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

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final Map<String, DateTime> _localReadOverrides = <String, DateTime>{};
  final ChatApiService _chatApi = ChatApiService.instance;

  @override
  void initState() {
    super.initState();
    _loadLocalReadOverrides();
  }

  String _chatReadOverrideKey(String chatRoomId) =>
      'chat_read_override_${widget.userId}_$chatRoomId';

  Future<void> _loadLocalReadOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    final overrides = <String, DateTime>{};
    final prefix = 'chat_read_override_${widget.userId}_';
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(prefix)) continue;
      final rawValue = prefs.getInt(key);
      if (rawValue == null) continue;
      final chatRoomId = key.substring(prefix.length);
      overrides[chatRoomId] = DateTime.fromMillisecondsSinceEpoch(rawValue);
    }
    if (!mounted) return;
    setState(() {
      _localReadOverrides
        ..clear()
        ..addAll(overrides);
    });
  }

  Future<void> _setLocalReadOverride(
    String chatRoomId,
    Map<String, dynamic> chatData,
  ) async {
    final readTimestamp = _resolveReadTimestamp(chatData);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _chatReadOverrideKey(chatRoomId),
      readTimestamp.millisecondsSinceEpoch,
    );
    if (!mounted) return;
    setState(() {
      _localReadOverrides[chatRoomId] = readTimestamp;
    });
  }

  DateTime? _readTimestampForUser(Map<String, dynamic> chatData) {
    final lastReadAt = Map<String, dynamic>.from(
      chatData['lastReadAt'] as Map? ?? <String, dynamic>{},
    );
    final rawValue = lastReadAt[widget.userId];
    if (rawValue is String) return DateTime.tryParse(rawValue);
    if (rawValue is DateTime) return rawValue;
    return null;
  }

  DateTime _resolveReadTimestamp(Map<String, dynamic> chatData) {
    final lastMessageTime = chatData['lastMessageTime'];
    if (lastMessageTime is String) {
      return DateTime.tryParse(lastMessageTime) ?? DateTime.now();
    }
    if (lastMessageTime is DateTime) return lastMessageTime;

    final updatedAt = chatData['updatedAt'];
    if (updatedAt is String) {
      return DateTime.tryParse(updatedAt) ?? DateTime.now();
    }
    if (updatedAt is DateTime) return updatedAt;

    return DateTime.now();
  }

  int _extractUnreadCount(String chatRoomId, Map<String, dynamic> chatData) {
    final lastMessageTime = _resolveChatSortTime(chatData);
    final lastReadAt = _readTimestampForUser(chatData);
    final localReadAt = _localReadOverrides[chatRoomId];
    final effectiveReadAt = [
      if (lastReadAt != null) lastReadAt,
      if (localReadAt != null) localReadAt,
    ].fold<DateTime?>(
      null,
      (latest, candidate) =>
          latest == null || candidate.isAfter(latest) ? candidate : latest,
    );
    if (effectiveReadAt != null && !lastMessageTime.isAfter(effectiveReadAt)) {
      return 0;
    }

    final unreadCounts = Map<String, dynamic>.from(
      chatData['unreadCounts'] as Map? ?? <String, dynamic>{},
    );
    if (unreadCounts.containsKey(widget.userId)) {
      final rawValue = unreadCounts[widget.userId];
      if (rawValue is int) return rawValue;
      if (rawValue is num) return rawValue.toInt();
    }
    final lastSenderId = (chatData['lastSenderId'] as String?)?.trim() ?? '';
    if (lastSenderId.isNotEmpty &&
        lastSenderId != widget.userId &&
        (effectiveReadAt == null || lastMessageTime.isAfter(effectiveReadAt))) {
      return 1;
    }
    return 0;
  }

  DateTime _resolveChatSortTime(Map<String, dynamic> chatData) {
    final lastMessageTime = chatData['lastMessageTime'];
    if (lastMessageTime is String) {
      return DateTime.tryParse(lastMessageTime) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    if (lastMessageTime is DateTime) {
      return lastMessageTime;
    }

    final updatedAt = chatData['updatedAt'];
    if (updatedAt is String) {
      return DateTime.tryParse(updatedAt) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    if (updatedAt is DateTime) {
      return updatedAt;
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
      final rooms = await _chatApi.fetchRooms(widget.userId);

      if (rooms.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No messages to mark as read.')),
        );
        return;
      }

      for (final room in rooms) {
        final roomId = room['chatRoomId']?.toString() ?? '';
        if (roomId.isEmpty) continue;
        await _chatApi.markRead(roomId);
        await _setLocalReadOverride(roomId, room);
      }

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
    await _chatApi.markRead(chatRoomId);
  }

  Future<void> _createOrOpenGroupChat(BuildContext context) async {
    final userData = await UserService.getUserData();
    final allUsers = await AdminUserApiService.instance.fetchUsers();

    Set<String> companyKeys(Map<String, dynamic> data) {
      final keys = <String>{};
      for (final field in const [
        'companyId',
        'activeCompanyId',
        'companyCode',
        'activeCompanyCode',
        'companyName',
        'company',
      ]) {
        final value = (data[field] as String?)?.trim().toLowerCase();
        if (value != null && value.isNotEmpty) {
          keys.add('$field:$value');
        }
      }
      return keys;
    }

    String displayNameFor(Map<String, dynamic> data) {
      for (final field in const ['username', 'fullName', 'name', 'email']) {
        final value = (data[field] as String?)?.trim();
        if (value != null && value.isNotEmpty) return value;
      }
      return 'Mentee';
    }

    final coachCompanyKeys = {
      ...companyKeys(userData),
      ...companyKeys(userData),
    };
    final eligibleMentees = allUsers.where((user) {
      if (user.id == widget.userId) return false;
      final data = <String, dynamic>{
        'companyId': user.companyCode,
        'companyCode': user.companyCode,
        'companyName': user.companyName,
        'company': user.companyName,
      };
      if (coachCompanyKeys.isEmpty) return true;
      return companyKeys(data).intersection(coachCompanyKeys).isNotEmpty;
    }).toList();

    if (eligibleMentees.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Add same-company mentees first to create a group chat.'),
        ),
      );
      return;
    }

    final teamTitle = (widget.groupName ?? '').trim().isNotEmpty
        ? widget.groupName!.trim()
        : ((userData['fullName'] as String?)?.trim().isNotEmpty == true
            ? (userData['fullName'] as String).trim()
            : 'My Team');
    final coachProfilePic =
        (userData['profilePic'] as String?)?.trim().isNotEmpty == true
            ? (userData['profilePic'] as String).trim()
            : (userData['profilePic'] as String?)?.trim() ?? '';

    if (!context.mounted) return;
    final groupNameController = TextEditingController(text: teamTitle);
    final selectedIds = eligibleMentees.map((doc) => doc.id).toSet();
    final selection = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 18,
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 18,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Create group chat',
                      style: Theme.of(sheetContext)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: groupNameController,
                      decoration: const InputDecoration(
                        labelText: 'Group name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Same-company mentees',
                      style: Theme.of(sheetContext)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: ListView(
                        shrinkWrap: true,
                        children: eligibleMentees.map((user) {
                          final data = <String, dynamic>{
                            'email': user.email,
                            'profilePic': user.profilePic,
                            'name': user.name,
                          };
                          final checked = selectedIds.contains(user.id);
                          return CheckboxListTile(
                            value: checked,
                            onChanged: (value) {
                              setModalState(() {
                                if (value == true) {
                                  selectedIds.add(user.id);
                                } else {
                                  selectedIds.remove(user.id);
                                }
                              });
                            },
                            title: Text(displayNameFor(data)),
                            subtitle: Text(
                              (data['email'] as String?)?.trim() ?? '',
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: selectedIds.isEmpty
                                ? null
                                : () {
                                    Navigator.pop(sheetContext, {
                                      'name': groupNameController.text.trim(),
                                      'ids': selectedIds.toList(),
                                    });
                                  },
                            child: const Text('Create'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    groupNameController.dispose();
    if (selection == null) return;

    final selectedMenteeIds =
        List<String>.from(selection['ids'] as List? ?? const []);
    if (selectedMenteeIds.isEmpty) return;
    final selectedMentees =
        eligibleMentees.where((user) => selectedMenteeIds.contains(user.id));
    final selectedGroupTitle =
        (selection['name'] as String?)?.trim().isNotEmpty == true
            ? (selection['name'] as String).trim()
            : teamTitle;

    final participantIds = <String>{widget.userId};
    final participantNames = <String, String>{widget.userId: widget.userName};
    final participantProfiles = <String, String>{
      widget.userId: coachProfilePic
    };

    for (final mentee in selectedMentees) {
      final data = <String, dynamic>{
        'email': mentee.email,
        'profilePic': mentee.profilePic,
        'name': mentee.name,
      };
      participantIds.add(mentee.id);
      participantNames[mentee.id] = displayNameFor(data);
      participantProfiles[mentee.id] =
          (data['profilePic'] as String?)?.trim() ?? '';
    }

    final chatRoomId = participantIds.toList()..sort();
    final roomId = chatRoomId.join('_');
    await _chatApi.saveRoom({
      'id': roomId,
      'is_group_chat': true,
      'group_name': selectedGroupTitle,
      'group_profile_pic': coachProfilePic,
      'participants': participantIds.toList(),
      'participant_names': participantNames,
      'participant_profiles': participantProfiles,
      'unread_counts': {
        for (final participantId in participantIds) participantId: 0,
      },
      'last_read_at': {
        widget.userId: DateTime.now().toIso8601String(),
      },
      'coach_id': widget.userId,
      'coach_name': teamTitle,
      'company_id': (userData['companyId'] as String?)?.trim(),
      'company_code': (userData['companyCode'] as String?)?.trim(),
      'company_name': (userData['companyName'] as String?)?.trim(),
    });

    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatRoomScreen(
          coach: Coach(
            id: widget.userId,
            name: selectedGroupTitle,
            profilePic: coachProfilePic,
            backgroundColor: const Color(0xFF90A17D),
          ),
          userId: widget.userId,
          userName: widget.userName,
          chatRoomId: roomId,
          chatTitle: selectedGroupTitle,
          chatProfilePic: coachProfilePic,
          isGroupChat: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        return Theme(
          data: AppTheme.company(companyTheme),
          child: Scaffold(
            backgroundColor: companyTheme.backgroundColor,
            appBar: AppBar(
              title: Text(
                'My Messages',
                style: TextStyle(
                  color: companyTheme.inkColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              backgroundColor: companyTheme.surfaceColor,
              foregroundColor: companyTheme.inkColor,
              iconTheme: IconThemeData(color: companyTheme.inkColor),
              actions: [
                IconButton(
                  icon: const Icon(Icons.done_all),
                  tooltip: 'Read all',
                  onPressed: () => _markAllChatsAsRead(context),
                ),
                if (widget.allowGroupChat)
                  IconButton(
                    icon: const Icon(Icons.groups_2_outlined),
                    onPressed: () => _createOrOpenGroupChat(context),
                  ),
              ],
            ),
            body: StreamBuilder<List<Map<String, dynamic>>>(
              stream: ChatApiService.instance.watchRooms(widget.userId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = [...?snapshot.data]..sort((a, b) {
                    final aTime = _resolveChatSortTime(a);
                    final bTime = _resolveChatSortTime(b);
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
                    final chatData = docs[index];
                    final participants = List<String>.from(
                        chatData['participants'] as List? ?? []);
                    final participantNames = Map<String, dynamic>.from(
                      chatData['participantNames'] as Map? ?? {},
                    );
                    final otherParticipantId = participants.firstWhere(
                      (participantId) => participantId != widget.userId,
                      orElse: () => chatData['coachId'] as String? ?? '',
                    );
                    final otherName = chatData['isGroupChat'] == true
                        ? (chatData['groupName'] as String?)?.trim() ??
                            'My Team'
                        : participantNames[otherParticipantId] as String? ??
                            (chatData['coachId'] == widget.userId
                                ? chatData['userName'] as String? ?? 'User'
                                : chatData['coachName'] as String? ?? 'Coach');
                    final lastMessage =
                        chatData['lastMessage'] as String? ?? '';
                    final lastMessageTime = _resolveChatSortTime(chatData);
                    final unreadCount =
                        _extractUnreadCount(chatData['chatRoomId'] as String? ?? '', chatData);
                    final isGroupChat = chatData['isGroupChat'] == true;
                    final peerProfilePic =
                        _resolvePeerProfilePic(chatData, otherParticipantId);

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
                        backgroundImage: peerProfilePic.isNotEmpty
                            ? NetworkImage(peerProfilePic)
                            : null,
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
                      onTap: () async {
                        final navigator = Navigator.of(context);
                        await _setLocalReadOverride(chatData['chatRoomId'] as String? ?? '', chatData);
                        _markChatAsReadById(chatData['chatRoomId'] as String? ?? '');
                        if (!mounted) return;
                        await navigator.push(
                          MaterialPageRoute(
                            builder: (context) => ChatRoomScreen(
                              coach: peer,
                              userId: widget.userId,
                              userName: widget.userName,
                              chatRoomId: chatData['chatRoomId'] as String? ?? '',
                              chatTitle: isGroupChat ? otherName : null,
                              chatProfilePic:
                                  isGroupChat ? peerProfilePic : null,
                              isGroupChat: isGroupChat,
                            ),
                          ),
                        );
                        await _setLocalReadOverride(chatData['chatRoomId'] as String? ?? '', chatData);
                        await _markChatAsReadById(chatData['chatRoomId'] as String? ?? '');
                        if (!mounted) return;
                        setState(() {});
                      },
                    );
                  },
                );
              },
            ),
          ),
        );
      },
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
