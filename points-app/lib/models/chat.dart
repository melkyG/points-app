import 'package:cloud_firestore/cloud_firestore.dart';

class Chat {
  final String id;
  final List<String> participants;
  final Timestamp? createdAt;

  Chat({required this.id, required this.participants, this.createdAt});

  factory Chat.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final participants = <String>[];
    final raw = data['participants'];
    if (raw is List) {
      for (final v in raw) {
        if (v is String) participants.add(v);
      }
    }
    return Chat(id: doc.id, participants: participants, createdAt: data['createdAt'] as Timestamp?);
  }

  Map<String, dynamic> toMap() => {
        'participants': participants,
        'createdAt': createdAt,
      };
}
