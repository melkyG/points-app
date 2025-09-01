import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/navigation_provider.dart';
import 'friend_search_page.dart';
import 'friend_requests_page.dart';

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
            children: const [
              FriendsTab(),
              Center(child: Text('Chats tab', style: TextStyle(fontSize: 18))),
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
  // For now show a placeholder friends list. This can be replaced
  // by a Firestore-backed friends query later.
  final List<Map<String, String>> _friends = [];

  @override
  Widget build(BuildContext context) {
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
                    );
                  },
                ),
        ),
      ],
    );
  }
}
