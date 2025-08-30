import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import 'package:http/http.dart' as http;

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
            child: TabBar(
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: Theme.of(context).textTheme.bodySmall?.color,
              tabs: const [Tab(text: 'Friends'), Tab(text: 'Chats')],
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
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  // Track per-user friend request status locally: 'add'|'sent'|'friends'
  final Map<String, String> _friendStatus = {};

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Search users by name or email',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    // Debounce input and call backend search
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), () => _performSearch(v));
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Minimal search button triggers immediate search
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => _performSearch(_searchController.text),
              ),
            ],
          ),
        ),
        // Placeholder ListView for results (empty now).
        Expanded(
          child: _results.isEmpty
              ? Center(child: Text(_searchController.text.isEmpty ? 'No results' : 'No matches'))
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final item = _results[index];
                    final account = item['accountName'] ?? '<no-name>';
                    final email = item['email'] ?? '';
                    final userId = item['userId']?.toString() ?? '';
                    final status = _friendStatus[userId] ?? 'add';

                    String buttonText;
                    bool disabled = false;
                    switch (status) {
                      case 'sent':
                        buttonText = 'Sent';
                        disabled = true;
                        break;
                      case 'friends':
                        buttonText = 'Friends';
                        disabled = true;
                        break;
                      default:
                        buttonText = 'Add';
                    }

                    return ListTile(
                      title: Text(account),
                      subtitle: Text(email),
                      trailing: ElevatedButton(
                        onPressed: disabled
                            ? null
                            : () => _onAddPressed(userId),
                        child: Text(buttonText),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _onAddPressed(String userId) {
    if (userId.isEmpty) return;
    // Optimistic update
    setState(() {
      _friendStatus[userId] = 'sent';
    });
    // Fire-and-forget async call to backend
    _sendFriendRequest(userId).then((ok) {
      if (!ok) {
        // revert
        setState(() {
          _friendStatus[userId] = 'add';
        });
      }
    });
  }

  Future<bool> _sendFriendRequest(String receiverId) async {
    // Try to obtain a valid backend HS256 token from the auth provider.
    var user = ref.read(authProvider);
    String? token = user?.token?.trim();
    String? senderId = user?.uid;

    // If missing, attempt one refresh and re-read
    if (token == null || token.isEmpty) {
      // Attempt to refresh the token via auth notifier; this may log out on failure.
      try {
        await ref.read(authProvider.notifier).refresh();
      } catch (_) {}
      user = ref.read(authProvider);
      token = user?.token?.trim();
      senderId = user?.uid;
    }

    if (token == null || token.isEmpty || senderId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not authenticated')));
      }
      return false;
    }

    // Basic token sanity check: JWT should have three parts separated by '.'
    final parts = token.split('.');
    if (parts.length != 3) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid token format')));
      return false;
    }

    // Check header alg is HS256 and check expiry. If expired, try refresh once.
    bool attemptedRefresh = false;
    bool needsRetry = false;

    for (;;) {
      try {
        final headerRaw = parts[0];
        final payloadRaw = parts[1];
        String normalized = base64Url.normalize(headerRaw);
        final headerJson = json.decode(utf8.decode(base64Url.decode(normalized))) as Map<String, dynamic>;
        final alg = headerJson['alg'] as String?;
        if (alg != 'HS256') {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Token algorithm not supported')));
          return false;
        }

        // Check exp
        normalized = base64Url.normalize(payloadRaw);
        final payloadJson = json.decode(utf8.decode(base64Url.decode(normalized))) as Map<String, dynamic>;
        final exp = payloadJson['exp'] as int?;
        if (exp != null) {
          final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
          if (exp < now) {
            // expired -> try refresh once
            if (!attemptedRefresh) {
              attemptedRefresh = true;
              needsRetry = true;
              await ref.read(authProvider.notifier).refresh();
              user = ref.read(authProvider);
              token = user?.token?.trim();
              senderId = user?.uid;
              if (token == null || token.isEmpty || senderId == null) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not authenticated')));
                return false;
              }
              // recompute parts and loop to re-validate
              if (token.split('.').length != 3) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid token format after refresh')));
                return false;
              }
              // update parts and continue loop
              parts.setRange(0, 3, token.split('.'));
              continue;
            } else {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Token expired')));
              return false;
            }
          }
        }
        break;
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invalid token: $e')));
        return false;
      }
    }

    final uri = Uri.parse('http://127.0.0.1:8000/friend_requests');
    try {
      final headers = {
        'Content-Type': 'application/json',
        // Ensure exact formatting 'Bearer <token>' with no extra quoting
        'Authorization': 'Bearer $token',
        'authorization': 'Bearer $token',
        'auth-header': 'Bearer $token',
      };

      final resp = await http.post(uri, headers: headers, body: json.encode({'senderId': senderId, 'receiverId': receiverId}));

      if (resp.statusCode == 201) {
        return true;
      }

      String msg = 'Failed to send request: HTTP ${resp.statusCode}';
      try {
        final body = json.decode(resp.body);
        if (body is Map && body['detail'] != null) msg = body['detail'].toString();
      } catch (_) {}
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return false;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Network error: $e')));
      return false;
    }
  }

  Future<void> _performSearch(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }

    try {
      final uri = Uri.parse('http://127.0.0.1:8000/users/search').replace(queryParameters: {'query': query});
      final resp = await http.get(uri);
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data is List) {
          setState(() => _results = List<Map<String, dynamic>>.from(data));
          return;
        }
      }
      setState(() => _results = []);
    } catch (_) {
      setState(() => _results = []);
    }
  }
}
