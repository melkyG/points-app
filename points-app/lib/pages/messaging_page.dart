import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'friend_search_page.dart';
import 'friend_requests_page.dart';

class MessagingPage extends StatelessWidget {
  const MessagingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TabBar(
                      labelColor: Theme.of(context).colorScheme.primary,
                      unselectedLabelColor: Theme.of(context).textTheme.bodySmall?.color,
                      tabs: const [Tab(text: 'Friends'), Tab(text: 'Chats')],
                    ),
                  ),
                  // Header no longer contains action icons; icons will appear inside the Friends tab body.
                ],
              ),
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                FriendsTab(),
                Center(child: Text('Chats tab', style: TextStyle(fontSize: 18))),
              ],
            ),
          ),
        ],
      ),
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
