import 'package:cloud_firestore/cloud_firestore.dart';

class Message {
  final String id;
  final String senderId;
  final String text;
  final Timestamp? timestamp;
  String status;

  Message(
      {required this.id,
      required this.senderId,
      required this.text,
      this.timestamp,
      required this.status});

  factory Message.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return Message(
      id: doc.id,
      senderId: (data['senderId'] as String?) ?? '',
      text: (data['text'] as String?) ?? '',
      timestamp: data['timestamp'] as Timestamp?,
      status: (data['status'] as String?) ?? 'unread',
    );
  }

  Map<String, dynamic> toMap() => {
        'senderId': senderId,
        'text': text,
        'timestamp': timestamp,
        'status': status,
      };
}
