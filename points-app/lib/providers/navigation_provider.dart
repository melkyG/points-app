import 'package:flutter_riverpod/flutter_riverpod.dart';

// Riverpod provider managing the selected bottom tab index.
final selectedIndexProvider = StateProvider<int>((ref) => 0);

// Provider to track the active tab inside the MessagingPage (0 = Friends, 1 = Chats)
final messagingTabIndexProvider = StateProvider<int>((ref) => 0);
