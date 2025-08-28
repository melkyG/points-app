import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              children: [
                const UserAccountsDrawerHeader(
                  accountName: Text('Account Name'),
                  accountEmail: Text('email@example.com'),
                ),
                ListTile(
                  leading: const Icon(Icons.person),
                  title: const Text('Account'),
                  onTap: () {
                    // TODO: Show account details or navigate when implemented.
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: const Text('Settings'),
                  onTap: () {
                    // TODO: Open settings screen when implemented.
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
            // Logout button aligned at the bottom
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Consumer(
                builder: (context, ref, _) {
                  return ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Logout'),
                    onTap: () async {
                      await ref.read(authProvider.notifier).logout();
                      // Clear navigation and return to login
                      Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
