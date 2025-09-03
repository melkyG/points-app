import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/message.dart';

class ChatService {
  ChatService({FirebaseFirestore? firestore}) : _fs = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _fs;

  CollectionReference<Map<String, dynamic>> get _chats => _fs.collection('chats');

  /// Creates a chat document with the provided participant IDs.
  /// Returns the created chat's document id.
  Future<String> createChat(List<String> participantIds) async {
    final docRef = await _chats.add({
      'participants': participantIds,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  /// Finds an existing 1-on-1 chat for users [a] and [b], or creates one and returns its id.
  /// This performs a query for chats that contain [a], then inspects the participants
  /// array to find an exact 2-person match containing [b]. If none found, a new chat is created.
  Future<String> getOrCreateChatForUsers(String a, String b) async {
    // Query chats containing user 'a'
    final snap = await _chats.where('participants', arrayContains: a).get();

    for (final doc in snap.docs) {
      final data = doc.data();
      final raw = data['participants'];
      if (raw is List && raw.length == 2) {
        final p0 = raw[0]?.toString();
        final p1 = raw[1]?.toString();
        if ((p0 == a && p1 == b) || (p0 == b && p1 == a)) {
          return doc.id;
        }
      }
    }

    // Not found — create a new chat document
    final docRef = await _chats.add({
      'participants': [a, b],
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  /// Sends a message in the chat's `messages` subcollection.
  Future<void> sendMessage(String chatId, String senderId, String text) async {
    final messages = _chats.doc(chatId).collection('messages');
    await messages.add({
      'senderId': senderId,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Streams messages for [chatId], ordered by `timestamp` ascending.
  Stream<List<Message>> getMessages(String chatId) {
    final messages = _chats.doc(chatId).collection('messages').orderBy('timestamp', descending: false);
    return messages.snapshots().map((snap) => snap.docs.map((d) => Message.fromDocument(d)).toList());
  }
}
