import 'package:flutter/material.dart';

class AccountPage extends StatelessWidget {
  final GlobalKey<ScaffoldState>? scaffoldKey;
  const AccountPage({super.key, this.scaffoldKey});

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
        title: const Text('Account'),
        centerTitle: true,
      ),
      body: const Center(
        child: Text('Account placeholder', style: TextStyle(fontSize: 18)),
      ),
    );
  }
}
