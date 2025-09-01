import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

class FriendSearchPage extends ConsumerStatefulWidget {
  const FriendSearchPage({super.key});

  @override
  ConsumerState<FriendSearchPage> createState() => _FriendSearchPageState();
}

class _FriendSearchPageState extends ConsumerState<FriendSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  final Map<String, String> _friendStatus = {};
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _friendSubs = {};

  @override
  void dispose() {
    for (final sub in _friendSubs.values) {
      try {
        sub.cancel();
      } catch (_) {}
    }
    _friendSubs.clear();
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Search Friends'),
      ),
      body: Column(
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
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 300), () => _performSearch(v));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _performSearch(_searchController.text),
                ),
              ],
            ),
          ),
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
                          onPressed: disabled ? null : () => _onAddPressed(userId),
                          child: Text(buttonText),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _onAddPressed(String userId) {
    if (userId.isEmpty) return;
    setState(() {
      _friendStatus[userId] = 'sent';
    });
    _sendFriendRequest(userId).then((ok) {
      if (!ok) {
        setState(() {
          _friendStatus[userId] = 'add';
        });
      }
    });
  }

  Future<bool> _sendFriendRequest(String receiverId) async {
    final current = ref.read(authProvider);
    if (current == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not authenticated')));
      return false;
    }

    String token = current.token.trim();
    String senderId = current.uid;

    if (token.isEmpty) {
      try {
        await ref.read(authProvider.notifier).refresh();
      } catch (_) {}
      final refreshed = ref.read(authProvider);
      if (refreshed == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not authenticated')));
        return false;
      }
      token = refreshed.token.trim();
      senderId = refreshed.uid;
    }

    if (token.isEmpty || senderId.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not authenticated')));
      return false;
    }

    final parts = token.split('.');
    if (parts.length != 3) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid token format')));
      return false;
    }

    String _normalizeBase64(String input) {
      final mod = input.length % 4;
      if (mod == 0) return input;
      return input + List.filled(4 - mod, '=').join();
    }

    try {
      final headerJson = json.decode(utf8.decode(base64Url.decode(_normalizeBase64(parts[0])))) as Map<String, dynamic>;
      final alg = headerJson['alg'] as String?;
      if (alg != 'HS256') {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Token algorithm not supported')));
        return false;
      }

      final payloadJson = json.decode(utf8.decode(base64Url.decode(_normalizeBase64(parts[1])))) as Map<String, dynamic>;
      final exp = payloadJson['exp'];
      if (exp is int) {
        final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
        if (exp < now) {
          try {
            await ref.read(authProvider.notifier).refresh();
          } catch (_) {}
          final refreshed = ref.read(authProvider);
          if (refreshed == null) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not authenticated')));
            return false;
          }
          token = refreshed.token.trim();
          senderId = refreshed.uid;
          if (token.isEmpty || senderId.isEmpty) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not authenticated')));
            return false;
          }
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invalid token: $e')));
      return false;
    }

    final uri = Uri.parse('http://127.0.0.1:8000/friend_requests');
    try {
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
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
      _stopAllListeners();
      return;
    }

    try {
      final uri = Uri.parse('http://127.0.0.1:8000/users/search').replace(queryParameters: {'query': query});
      final resp = await http.get(uri);
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data is List) {
          setState(() => _results = List<Map<String, dynamic>>.from(data));
          _startListenersForResults();
          return;
        }
      }
      setState(() => _results = []);
      _stopAllListeners();
    } catch (_) {
      setState(() => _results = []);
      _stopAllListeners();
    }
  }

  void _startListenersForResults() {
    final user = ref.read(authProvider);
    final myUid = user?.uid;

    if (myUid == null) {
      _stopAllListeners();
      return;
    }

    final seen = <String>{};
    for (final item in _results) {
      final targetId = item['userId']?.toString() ?? '';
      if (targetId.isEmpty) continue;
      seen.add(targetId);
      if (_friendSubs.containsKey(targetId)) continue;

      final q = FirebaseFirestore.instance
          .collection('friend_requests')
          .where('senderId', isEqualTo: myUid)
          .where('receiverId', isEqualTo: targetId)
          .limit(1)
          .snapshots();

      final sub = q.listen((snap) {
        if (snap.docs.isEmpty) {
          setState(() => _friendStatus[targetId] = 'add');
        } else {
          final data = snap.docs.first.data();
          final status = (data['status'] as String?) ?? 'pending';
          setState(() {
            if (status == 'pending') {
              _friendStatus[targetId] = 'sent';
            } else if (status == 'accepted') {
              _friendStatus[targetId] = 'friends';
            } else {
              _friendStatus[targetId] = 'add';
            }
          });
        }
      }, onError: (e) {
        setState(() => _friendStatus[targetId] = 'add');
      });

      _friendSubs[targetId] = sub;
    }

    final toRemove = _friendSubs.keys.where((k) => !seen.contains(k)).toList();
    for (final k in toRemove) {
      try {
        _friendSubs[k]?.cancel();
      } catch (_) {}
      _friendSubs.remove(k);
      setState(() => _friendStatus.remove(k));
    }
  }

  void _stopAllListeners() {
    for (final sub in _friendSubs.values) {
      try {
        sub.cancel();
      } catch (_) {}
    }
    _friendSubs.clear();
  }
}
