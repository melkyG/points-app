import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/message.dart';
import '../services/chat_service.dart';
import '../providers/auth_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String chatId;
  const ChatScreen({super.key, required this.chatId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ChatService _svc = ChatService();
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  // null value => fetch in progress, non-null => displayName available
  final Map<String, String?> _nameCache = {};
  // chat participants (uids)
  List<String> _participants = [];
  StreamSubscription<List<Message>>? _messageSub;
  List<Message> _messages = [];

  @override
  void initState() {
    super.initState();
    // Subscribe to messages to enable scroll-to-bottom when new messages arrive.
    _messageSub = _svc.getMessages(widget.chatId).listen((list) {
      setState(() {
        _messages = list;
      });
      SchedulerBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      // prefetch sender names for remote senders
      for (final m in list) {
        if (!_nameCache.containsKey(m.senderId)) _fetchAndCacheName(m.senderId);
      }
    });
    // Also prefetch participant names (other user) so we show displayName instead of UID early.
    Future.microtask(() => _ensureParticipantNames());
  }

  Future<void> _ensureParticipantNames() async {
    final myUid = ref.read(authProvider)?.uid ?? '';
    if (myUid.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).get();
      final data = doc.data();
      final parts = (data != null && data['participants'] is List) ? List.from(data['participants']) : <dynamic>[];
      _participants = parts.map((p) => p?.toString() ?? '').where((s) => s.isNotEmpty).cast<String>().toList();
      for (final p in _participants) {
        if (_nameCache.containsKey(p)) continue;
        if (p == myUid) {
          _nameCache[p] = 'You';
        } else {
          await _fetchAndCacheName(p);
        }
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _fetchAndCacheName(String uid) async {
    if (uid.isEmpty) return;
    // If already fetched or fetching, skip
    if (_nameCache.containsKey(uid)) return;
    final me = ref.read(authProvider)?.uid ?? '';
    if (uid == me) {
      _nameCache[uid] = 'You';
      if (mounted) setState(() {});
      return;
    }

    // mark as loading
    _nameCache[uid] = null;
    if (mounted) setState(() {});

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data();
      final name = (data != null && data['accountName'] is String) ? data['accountName'] as String : null;
      _nameCache[uid] = name ?? uid;
    } catch (_) {
      _nameCache[uid] = uid;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    try {
      _messageSub?.cancel();
    } catch (_) {}
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  Future<void> _send() async {
    final txt = _ctrl.text.trim();
    if (txt.isEmpty) return;
    final uid = ref.read(authProvider)?.uid;
    if (uid == null) return;
    _ctrl.clear();
    try {
      await _svc.sendMessage(widget.chatId, uid, txt);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Send failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = ref.read(authProvider)?.uid ?? '';

    // Determine the other participant's UID (the friend)
    String otherUid = '';
    if (_participants.isNotEmpty) {
      otherUid = _participants.firstWhere((p) => p != myUid, orElse: () => _participants.first);
    } else if (_messages.isNotEmpty) {
      // fallback: use sender of first message that's not me
      final possible = _messages.firstWhere((m) => m.senderId != myUid, orElse: () => _messages.first);
      otherUid = possible.senderId;
    }

    Widget appBarTitleWidget;
    if (otherUid.isEmpty) {
      // show shimmer-style placeholder while we resolve participants/name
      appBarTitleWidget = Container(
        width: 140,
        height: 18,
        decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(8)),
      );
    } else if (otherUid == myUid) {
      appBarTitleWidget = const Text('You');
    } else if (_nameCache.containsKey(otherUid)) {
      final name = _nameCache[otherUid];
      if (name == null) {
        // loading in progress -> show shimmer-like placeholder (do not show UID)
        appBarTitleWidget = Container(
          width: 140,
          height: 18,
          decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(8)),
        );
      } else {
        // name resolved (could be UID fallback if fetch failed and we stored uid)
        appBarTitleWidget = Text(name);
      }
    } else {
      // trigger fetch and show a shimmer-like placeholder until resolved
      _fetchAndCacheName(otherUid);
      appBarTitleWidget = Container(
        width: 140,
        height: 18,
        decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(8)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Defer unfocus and navigation slightly so the browser finishes pointer handling.
            Future.delayed(const Duration(milliseconds: 1), () {
              FocusScope.of(context).unfocus();
              Navigator.of(context).maybePop();
            });
          },
        ),
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Future.delayed(const Duration(milliseconds: 1), () => FocusScope.of(context).unfocus()),
          child: appBarTitleWidget,
        ),
        flexibleSpace: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Future.delayed(const Duration(milliseconds: 1), () => FocusScope.of(context).unfocus()),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(child: Text('No messages'))
                : ListView.builder(
                    controller: _scroll,
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final m = _messages[i];
                      final isMe = m.senderId == myUid;
                      final hasNameKey = _nameCache.containsKey(m.senderId);
                      final nameEntry = hasNameKey ? _nameCache[m.senderId] : null;
                      final bg = isMe ? Theme.of(context).colorScheme.primary : Colors.grey[300];
                      final textColor = isMe ? Colors.white : Colors.black87;
                      Widget nameWidget;
                      if (isMe) {
                        nameWidget = const Text('You', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600));
                      } else if (hasNameKey) {
                        // hasNameKey true means we have a cache entry; value may be null while loading
                        if (nameEntry == null) {
                          nameWidget = Container(
                            width: 80,
                            height: 12,
                            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(6)),
                          );
                        } else {
                          nameWidget = Text(nameEntry, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600));
                        }
                      } else {
                        // kick off fetch and show placeholder
                        _fetchAndCacheName(m.senderId);
                        nameWidget = Container(
                          width: 80,
                          height: 12,
                          decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(6)),
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Column(
                          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            nameWidget,
                            const SizedBox(height: 4),
                            Container(
                              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: Text(m.text, style: TextStyle(color: textColor)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      decoration: const InputDecoration(hintText: 'Message'),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.send), onPressed: _send)
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
