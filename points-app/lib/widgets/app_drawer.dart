import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
 

class AppDrawer extends ConsumerStatefulWidget {
  const AppDrawer({super.key});

  @override
  ConsumerState<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends ConsumerState<AppDrawer> {
  @override
  Widget build(BuildContext context) {
  // Debug: print the cached accountName from the provider to verify updates
  print(ref.watch(authProvider)?.accountName);
  final user = ref.watch(authProvider);
    final email = user?.email ?? '';
    final accountName = user?.accountName;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Top content: make scrollable if it grows
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    UserAccountsDrawerHeader(
                      accountName: accountName == null
                          ? const SizedBox(width: 120, height: 16, child: LinearProgressIndicator())
                          : Text(accountName),
                      accountEmail: Text(email.isNotEmpty ? email : 'email@example.com'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.person),
                      title: const Text('Account'),
                      onTap: () {
                        Navigator.pop(context);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.settings),
                      title: const Text('Settings'),
                      onTap: () {
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Logout button placed above the bottom banner
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Consumer(
                builder: (context, ref, _) {
                  return ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Logout'),
                    onTap: () {
                      // Show a blocking confirmation dialog
                      showDialog<void>(
                        context: context,
                        barrierDismissible: true,
                        builder: (dialogCtx) {
                          return AlertDialog(
                            title: const Center(child: Text('Confirm Logout?')),
                            actionsAlignment: MainAxisAlignment.center,
                            actions: [
                              TextButton(
                                onPressed: () {
                                  Navigator.of(dialogCtx).pop();
                                },
                                child: const Text('No'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  Navigator.of(dialogCtx).pop();
                                  await ref.read(authProvider.notifier).logout();
                                  Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
                                },
                                child: const Text('Yes'),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),

            // Bottom banner that matches the top header color and fills
            // the height equal to the BottomNavigationBar (so drawer bottom aligns)
            Container(
              height: kBottomNavigationBarHeight,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
