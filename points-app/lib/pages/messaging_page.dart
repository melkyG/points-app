import 'package:flutter/material.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/navigation_provider.dart';
import '../providers/auth_provider.dart';
import '../services/chat_service.dart';
import 'friend_search_page.dart';
import 'friend_requests_page.dart';
import 'chats_list_page.dart';
import 'chat_screen.dart';
import '../utils/navigation.dart';

class MessagingPage extends ConsumerStatefulWidget {
  const MessagingPage({super.key});

  @override
  ConsumerState<MessagingPage> createState() => _MessagingPageState();
}

class _MessagingPageState extends ConsumerState<MessagingPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        // update provider when tab settles
        ref.read(messagingTabIndexProvider.notifier).state = _tabController.index;
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep TabController in sync with provider changes. Using ref.listen inside
    // build is allowed for ConsumerState and registers a lifecycle-tied listener.
    ref.listen<int>(messagingTabIndexProvider, (prev, next) {
      if (!_tabController.indexIsChanging && _tabController.index != next) {
        _tabController.animateTo(next);
      }
    });
    return Column(
      children: [
        Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _tabController,
                    labelColor: Theme.of(context).colorScheme.primary,
                    unselectedLabelColor: Theme.of(context).textTheme.bodySmall?.color,
                    tabs: const [
                      Tab(icon: Icon(Icons.groups)),
                      Tab(icon: Icon(Icons.message)),
                    ],
                  ),
                ),
                // Header icons live inside the tab bodies
              ],
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              const FriendsTab(),
              // ChatsListPage shows real-time chats and will auto-open pending chat IDs
              // when requested from FriendsTab.
              const ChatsListPage(),
            ],
          ),
        ),
      ],
    );
  }
}

class FriendsTab extends ConsumerStatefulWidget {
  const FriendsTab({super.key});

  @override
  ConsumerState<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends ConsumerState<FriendsTab> {
  final List<Map<String, String>> _friends = [];

  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subSender;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subReceiver;
  // temp storage keyed by friend_request doc id; we'll merge/dedupe by friendId
  final Map<String, Map<String, String>> _tempByRequest = {};

  void _rebuildFriends() {
    final Map<String, Map<String, String>> byFriendId = {};
    for (final entry in _tempByRequest.values) {
      final friendId = entry['friendId'];
      if (friendId == null) continue;
      // dedupe by friendId (keep last written)
      byFriendId[friendId] = {'name': entry['name'] ?? '<no-name>', 'email': entry['email'] ?? ''};
    }
    setState(() {
      _friends
        ..clear()
        ..addAll(byFriendId.entries.map((entry) => {'friendId': entry.key, 'name': entry.value['name']!, 'email': entry.value['email']!}));
    });
  }

  void _startListeners() {
    final uid = ref.read(authProvider)?.uid;
    _subSender?.cancel();
    _subReceiver?.cancel();
    if (uid == null) return;

    final qSender = _fs.collection('friend_requests').where('senderId', isEqualTo: uid).where('status', isEqualTo: 'accepted');
    final qReceiver = _fs.collection('friend_requests').where('receiverId', isEqualTo: uid).where('status', isEqualTo: 'accepted');

    _subSender = qSender.snapshots().listen((snap) {
      for (final d in snap.docs) {
        final data = d.data();
        final friendId = data['receiverId'] as String?;
        final name = (data['receiverDisplayName'] as String?) ?? (data['receiverEmail'] as String?) ?? 'Unknown';
        final email = (data['receiverEmail'] as String?) ?? '';
        _tempByRequest[d.id] = {'friendId': friendId ?? '', 'name': name, 'email': email};
      }
      _rebuildFriends();
    });

    _subReceiver = qReceiver.snapshots().listen((snap) {
      for (final d in snap.docs) {
        final data = d.data();
        final friendId = data['senderId'] as String?;
        final name = (data['senderDisplayName'] as String?) ?? (data['senderEmail'] as String?) ?? 'Unknown';
        final email = (data['senderEmail'] as String?) ?? '';
        _tempByRequest[d.id] = {'friendId': friendId ?? '', 'name': name, 'email': email};
      }
      _rebuildFriends();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Ensure listeners are active when widget is built and auth state available
    // (didChangeDependencies also starts listeners; this is safe to call idempotently)
    if (_subSender == null && _subReceiver == null) {
      _startListeners();
    }
    return Column(
      children: [
        // Action icons row (only visible inside Friends tab body)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Search friends',
                icon: const Icon(Icons.search),
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FriendSearchPage()));
                },
              ),
              IconButton(
                tooltip: 'Friend requests',
                icon: const Icon(Icons.person_add),
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FriendRequestsPage()));
                },
              ),
            ],
          ),
        ),

        // Friends list area
        Expanded(
          child: _friends.isEmpty
              ? const Center(child: Text('No friends yet'))
              : ListView.builder(
                  itemCount: _friends.length,
                  itemBuilder: (context, index) {
                    final f = _friends[index];
                    return ListTile(
                      title: Text(f['name'] ?? '<no-name>'),
                      subtitle: Text(f['email'] ?? ''),
                      trailing: IconButton(
                        tooltip: 'Chat',
                        icon: const Icon(Icons.chat),
                        onPressed: () async {
                          final friendId = f['friendId'];
                          final myUid = ref.read(authProvider)?.uid ?? '';
                          if (friendId == null || myUid.isEmpty) return;
                          final svc = ChatService();
                          try {
                            final chatId = await svc.getOrCreateChatForUsers(myUid, friendId);
                            if (!mounted) return;
                            // switch bottom nav to Messaging (index 0) then switch inner tab to Chats (1)
                            ref.read(selectedIndexProvider.notifier).state = 0;
                            ref.read(messagingTabIndexProvider.notifier).state = 1;
                            // Schedule the push for the next frame so the tab switch takes effect
                            // and then push using the root navigator so back returns to the Chats tab.
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              rootNavigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId)));
                            });
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to open chat: $e')));
                          }
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
