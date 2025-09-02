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
    final messagingTab = ref.watch(messagingTabIndexProvider);
    String title;
    if (selectedIndex == 1) {
      title = 'Maps';
    } else {
      title = messagingTab == 0 ? 'Friends' : 'Chats';
    }

    // Simple mapping of tab index to page widgets.
    final pages = const [MessagingPage(), MapsPage()];

    return Scaffold(
      appBar: AppBar(
        // Place a custom leading drawer button but keep the title centered
        leading: Builder(builder: (ctx) {
          return IconButton(
            tooltip: 'Open menu',
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          );
        }),
        // Slightly reduce the app bar height and font size for the dynamic title
        toolbarHeight: 50,
        title: Text(
          title,
          style: const TextStyle(fontSize: 18),
        ),
        centerTitle: true,
      ),
      drawer: const AppDrawer(),
      body: IndexedStack(
        index: selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: SafeArea(
        child: Row(
          children: [
            // Expand the BottomNavigationBar to occupy remaining space
            Expanded(
              child: BottomNavigationBar(
                currentIndex: selectedIndex,
                onTap: (i) {
                  ref.read(selectedIndexProvider.notifier).state = i;
                  if (i == 0) {
                    // whenever we navigate into Messaging, default to Chats (index 1)
                    ref.read(messagingTabIndexProvider.notifier).state = 1;
                  }
                },
                items: const [
                  BottomNavigationBarItem(icon: Icon(Icons.message), label: 'Messaging'),
                  BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Maps'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
