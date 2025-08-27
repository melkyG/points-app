import 'package:flutter/material.dart';

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
              child: ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                onTap: () {
                  // TODO: Clear auth state / tokens here before navigating.
                  Navigator.pushReplacementNamed(context, '/login');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
