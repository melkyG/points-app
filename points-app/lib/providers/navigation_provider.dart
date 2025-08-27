import 'package:flutter_riverpod/flutter_riverpod.dart';

// Riverpod provider managing the selected bottom tab index.
final selectedIndexProvider = StateProvider<int>((ref) => 0);
