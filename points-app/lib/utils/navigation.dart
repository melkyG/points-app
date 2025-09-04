import 'package:flutter/widgets.dart';

// Global navigator key for root-level navigation
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

// Nested navigator key scoped to the Messaging tab. Use this to push
// ChatScreen inside the Messaging tab so the bottom navigation bar
// remains visible.
final GlobalKey<NavigatorState> messagingNavigatorKey = GlobalKey<NavigatorState>();
