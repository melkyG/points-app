import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

class FriendRequestsPage extends ConsumerStatefulWidget {
  const FriendRequestsPage({super.key});

  @override
  ConsumerState<FriendRequestsPage> createState() => _FriendRequestsPageState();
}

class _FriendRequestsPageState extends ConsumerState<FriendRequestsPage> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  List<Map<String, dynamic>> _requests = [];

  // Track accepted request IDs for this session/screen so they remain visible
  // until the user leaves the screen.
  final Set<String> _acceptedIds = {};

  @override
  void initState() {
    super.initState();
    // Listener will be started in didChangeDependencies where we can access provider
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _startListener();
  }

  void _startListener() {
    final user = ref.read(authProvider);
    final uid = user?.uid;
    _sub?.cancel();
    if (uid == null) return;

  _sub = _fs
    .collection('friend_requests')
    .where('receiverId', isEqualTo: uid)
    .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snap) {
      final items = snap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return data;
      }).toList();
      setState(() {
        _requests = items;
        // Remove accepted IDs which are no longer pending
        _acceptedIds.removeWhere((id) => !_requests.any((r) => r['id'] == id));
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _accept(String id) async {
    // Optimistically mark accepted in UI for this session
    setState(() => _acceptedIds.add(id));

    // Update Firestore (fire-and-forget). If this fails, the listener will
    // bring the UI back into sync, and accepted state will be removed.
    try {
      final docRef = _fs.collection('friend_requests').doc(id);

      // Read the request doc to determine sender/receiver for duplicate cleanup
      final doc = await docRef.get();
      if (!doc.exists) {
        // nothing to do
        return;
      }

      final data = doc.data();
      final senderId = data?['senderId'] as String?;
      final receiverId = data?['receiverId'] as String?;

      // Update this request to accepted
      await docRef.update({'status': 'accepted'});

      // If we have sender/receiver, find reverse-direction pending requests and delete them
      if (senderId != null && receiverId != null) {
        final q = await _fs
            .collection('friend_requests')
            .where('senderId', isEqualTo: receiverId)
            .where('receiverId', isEqualTo: senderId)
            .where('status', isEqualTo: 'pending')
            .get();

        if (q.docs.isNotEmpty) {
          final batch = _fs.batch();
          for (final d in q.docs) {
            batch.delete(d.reference);
          }
          await batch.commit();
        }
      }
    } catch (_) {
      // ignore errors for now; snapshot listener will resolve actual state
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Friend Requests')),
      body: _requests.isEmpty
          ? const Center(child: Text('No pending friend requests'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _requests.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final r = _requests[index];
                final id = r['id'] as String? ?? '';
                // Determine which side we are on and pick the other user's denormalized fields
                final currentUser = ref.read(authProvider);
                final uid = currentUser?.uid;
                final isSender = uid != null && (r['senderId'] as String?) == uid;

                String? displayName = isSender
                    ? (r['receiverDisplayName'] as String?)
                    : (r['senderDisplayName'] as String?);
                String? email = isSender ? (r['receiverEmail'] as String?) : (r['senderEmail'] as String?);

                // Fallback to old keys if denormalized fields are missing
                displayName ??= r['displayName'] as String?;
                email ??= r['email'] as String?;

                final name = displayName ?? email ?? 'Unknown';
                final titleText = (displayName != null || email != null) ? '${displayName ?? name} (${email ?? ''})' : name;
                // avatarUrl intentionally unused to match search list item style
                final accepted = _acceptedIds.contains(id);

                return ListTile(
                  // Use default ListTile padding and plain Text widgets to match search list items
                  title: Text(titleText),
                  subtitle: Text(r['message'] as String? ?? ''),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Tooltip(
                        message: accepted ? 'Accepted' : 'Accept',
                        child: ElevatedButton(
                          onPressed: accepted ? null : () => _accept(id),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accepted ? Colors.grey : Theme.of(context).colorScheme.primary,
                            minimumSize: const Size(40, 40),
                            padding: EdgeInsets.zero,
                          ),
                          child: const Icon(Icons.check),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Decline',
                        child: OutlinedButton(
                          onPressed: () {
                            // Decline not implemented yet per requirements
                          },
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(40, 40),
                            padding: EdgeInsets.zero,
                          ),
                          child: const Icon(Icons.close),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
