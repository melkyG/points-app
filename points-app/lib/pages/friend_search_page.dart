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
  final Map<String, List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?>> _friendSubs = {};
  // track latest status from queries in both directions
  final Map<String, String?> _friendStatusA = {}; // sender==me -> status
  final Map<String, String?> _friendStatusB = {}; // sender==target -> status

  @override
  void dispose() {
    for (final subs in _friendSubs.values) {
      for (final sub in subs) {
        try {
          sub?.cancel();
        } catch (_) {}
      }
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
          onTap: () => FocusScope.of(context).unfocus(),
          child: const Text('Search for Users'),
        ),
        flexibleSpace: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Future.delayed(const Duration(milliseconds: 1), () => FocusScope.of(context).unfocus()),
        ),
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
          // Filter out the current user from results so the signed-in account isn't shown
          final user = ref.read(authProvider);
          final myUid = user?.uid;
          final raw = List<Map<String, dynamic>>.from(data);
          final filtered = myUid == null ? raw : raw.where((e) => (e['userId']?.toString() ?? '') != myUid).toList();
          setState(() => _results = filtered);
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

      // Query A: current user -> target (to detect sent/pending/accepted)
      final qA = FirebaseFirestore.instance
          .collection('friend_requests')
          .where('senderId', isEqualTo: myUid)
          .where('receiverId', isEqualTo: targetId)
          .where('status', whereIn: ['pending', 'accepted'])
          .limit(1)
          .snapshots();

      // Query B: target -> current user (to detect accepted from other side)
      final qB = FirebaseFirestore.instance
          .collection('friend_requests')
          .where('senderId', isEqualTo: targetId)
          .where('receiverId', isEqualTo: myUid)
          .where('status', whereIn: ['pending', 'accepted'])
          .limit(1)
          .snapshots();

      StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subA;
      StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subB;

      void recompute() {
        final sa = _friendStatusA[targetId];
        final sb = _friendStatusB[targetId];
        if (sa == 'accepted' || sb == 'accepted') {
          setState(() => _friendStatus[targetId] = 'friends');
          return;
        }
        if (sa == 'pending') {
          setState(() => _friendStatus[targetId] = 'sent');
          return;
        }
        // default
        setState(() => _friendStatus[targetId] = 'add');
      }

      subA = qA.listen((snap) {
        if (snap.docs.isEmpty) {
          _friendStatusA.remove(targetId);
        } else {
          final data = snap.docs.first.data();
          _friendStatusA[targetId] = (data['status'] as String?) ?? 'pending';
        }
        recompute();
      }, onError: (e) {
        _friendStatusA.remove(targetId);
        recompute();
      });

      subB = qB.listen((snap) {
        if (snap.docs.isEmpty) {
          _friendStatusB.remove(targetId);
        } else {
          final data = snap.docs.first.data();
          _friendStatusB[targetId] = (data['status'] as String?) ?? 'pending';
        }
        recompute();
      }, onError: (e) {
        _friendStatusB.remove(targetId);
        recompute();
      });

      _friendSubs[targetId] = [subA, subB];
    }

    final toRemove = _friendSubs.keys.where((k) => !seen.contains(k)).toList();
    for (final k in toRemove) {
      try {
        for (final s in _friendSubs[k] ?? []) {
          try {
            s?.cancel();
          } catch (_) {}
        }
      } catch (_) {}
      _friendSubs.remove(k);
      _friendStatusA.remove(k);
      _friendStatusB.remove(k);
      setState(() => _friendStatus.remove(k));
    }
  }

  void _stopAllListeners() {
    for (final subs in _friendSubs.values) {
      for (final sub in subs) {
        try {
          sub?.cancel();
        } catch (_) {}
      }
    }
    _friendSubs.clear();
  }
}
