import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import 'chat_screen.dart';

class ChatsListPage extends ConsumerStatefulWidget {
  const ChatsListPage({super.key});

  @override
  ConsumerState<ChatsListPage> createState() => _ChatsListPageState();
}

class _ChatsListPageState extends ConsumerState<ChatsListPage> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  final List<Map<String, dynamic>> _chats = [];
  // ChatService not needed here after pending-open handling moved to FriendsTab
  // per-chat latest-message subscriptions
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _msgSubs = {};
  final Map<String, Map<String, dynamic>> _lastMessages = {};
  // name cache uid -> accountName? (null == loading)
  final Map<String, String?> _nameCache = {};
  // pending-related fields removed; kept simple

  void _startListener() {
    final uid = ref.read(authProvider)?.uid;
    _sub?.cancel();
    if (uid == null) return;

    final q = _fs.collection('chats').where('participants', arrayContains: uid);
    _sub = q.snapshots().listen((snap) {
      _chats.clear();
      for (final d in snap.docs) {
        final data = d.data();
        _chats.add({'id': d.id, 'participants': data['participants'] as List? ?? [], 'createdAt': data['createdAt']});
      }
      setState(() {});

  // ChatsListPage shows real-time chats; Pending-open handling moved to FriendsTab.
      // Ensure per-chat latest-message listeners are active for current chats
      final currentIds = _chats.map((c) => c['id'] as String).toSet();
      // cancel subs no longer needed
      final toRemove = _msgSubs.keys.where((k) => !currentIds.contains(k)).toList();
      for (final k in toRemove) {
        try {
          _msgSubs[k]?.cancel();
        } catch (_) {}
        _msgSubs.remove(k);
        _lastMessages.remove(k);
      }

      // start listeners for new chats
      for (final c in _chats) {
        final id = c['id'] as String;
        if (_msgSubs.containsKey(id)) continue;
        final sub = _fs
            .collection('chats')
            .doc(id)
            .collection('messages')
            .orderBy('timestamp', descending: true)
            .limit(1)
            .snapshots()
            .listen((ms) {
          if (ms.docs.isEmpty) {
            _lastMessages.remove(id);
          } else {
            final m = ms.docs.first.data();
            _lastMessages[id] = m;
            // Ensure we have name cache for sender and other participant
            final senderId = (m['senderId'] as String?) ?? '';
            if (senderId.isNotEmpty && !_nameCache.containsKey(senderId)) _fetchAndCacheName(senderId);
            final parts = c['participants'] as List;
            for (final p in parts) {
              final pid = p?.toString() ?? '';
              if (pid.isNotEmpty && !_nameCache.containsKey(pid)) _fetchAndCacheName(pid);
            }
          }
          if (mounted) setState(() {});
        });
        _msgSubs[id] = sub;
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    for (final s in _msgSubs.values) {
      try {
        s.cancel();
      } catch (_) {}
    }
    super.dispose();
  }

  Future<void> _fetchAndCacheName(String uid) async {
    // mark as loading
    _nameCache[uid] = null;
    try {
      final doc = await _fs.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data();
        final name = (data != null && data['accountName'] != null) ? data['accountName'].toString() : null;
        _nameCache[uid] = name;
      } else {
        _nameCache[uid] = null;
      }
    } catch (e) {
      _nameCache[uid] = null;
    }
    if (mounted) setState(() {});
  }

  // (pending chat handling removed; timer unused but keep field in case of future use)

  @override
  Widget build(BuildContext context) {
    if (_sub == null) _startListener();
    return Column(
      children: [
        Expanded(
          child: _chats.isEmpty
              ? const Center(child: Text('No chats yet'))
              : ListView.builder(
                  itemCount: _chats.length,
                  itemBuilder: (context, i) {
                    final c = _chats[i];
                    final id = c['id'] as String;
                    final parts = (c['participants'] as List).cast<String>();
                    final uid = ref.read(authProvider)?.uid;
                    final other = parts.firstWhere((p) => p != uid, orElse: () => parts.isNotEmpty ? parts.first : uid ?? '');

                    // Title: friend's display name (or 'You' if it's the current user)
                    String titleText;
                    if (other == uid) {
                      titleText = 'You';
                    } else if (_nameCache.containsKey(other)) {
                      titleText = _nameCache[other] ?? other;
                    } else {
                      // trigger fetch, show uid until resolved
                      _fetchAndCacheName(other);
                      titleText = other;
                    }

                    // Subtitle: last message if present
                    String? subtitleText;
                    final last = _lastMessages[id];
                    if (last != null && last.containsKey('text') && last.containsKey('senderId')) {
                      final text = (last['text'] ?? '').toString();
                      final senderId = (last['senderId'] ?? '').toString();
                      if (senderId == uid) {
                        subtitleText = 'You: $text';
                      } else {
                        String senderName;
                        if (_nameCache.containsKey(senderId)) {
                          senderName = _nameCache[senderId] ?? senderId;
                        } else {
                          _fetchAndCacheName(senderId);
                          senderName = senderId;
                        }
                        subtitleText = '$senderName: $text';
                      }
                    } else {
                      subtitleText = null;
                    }

                    return ListTile(
                      title: Text(titleText),
                      subtitle: subtitleText != null ? Text(subtitleText) : null,
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chatId: id)));
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
