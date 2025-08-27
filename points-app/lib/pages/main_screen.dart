import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/navigation_provider.dart';
import 'messaging_page.dart';
import 'maps_page.dart';
import '../widgets/app_drawer.dart';

class MainScreen extends ConsumerWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(selectedIndexProvider);

    // Simple mapping of tab index to page widgets.
    final pages = const [MessagingPage(), MapsPage()];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Points - Main'),
      ),
      drawer: const AppDrawer(), // Drawer slides over the content by default.
      body: IndexedStack(
        index: selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: (i) => ref.read(selectedIndexProvider.notifier).state = i,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.message), label: 'Messaging'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Maps'),
        ],
      ),
    );
  }
}
