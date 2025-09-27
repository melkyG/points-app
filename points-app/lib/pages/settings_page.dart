import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  final GlobalKey<ScaffoldState>? scaffoldKey;
  const SettingsPage({super.key, this.scaffoldKey});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop();
            // Add a delay before opening the drawer to make it feel slower
            Future.delayed(const Duration(milliseconds: 300), () {
              final state = scaffoldKey?.currentState;
              if (state != null && state.mounted) {
                state.openDrawer();
              }
            });
          },
        ),
        title: const Text('Settings'),
        centerTitle: true,
      ),
      body: const Center(
        child: Text('Settings placeholder', style: TextStyle(fontSize: 18)),
      ),
    );
  }
}
