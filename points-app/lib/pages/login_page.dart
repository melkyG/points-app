import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import 'package:flutter/foundation.dart'; // <-- add this import

// Single editable host selection used for local backend calls.
// Defaults: web -> 127.0.0.1, non-web (emulator) -> 10.0.2.2
const String _localHostForWeb = '127.0.0.1';
const String _localHostForEmulator = '10.0.2.2';
final String localHost = kIsWeb ? _localHostForWeb : _localHostForEmulator;

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _emailController = TextEditingController(text: 'test12@gmail.com');
  final _passwordController = TextEditingController(text: 'test12');
  bool _loading = false;

  Future<void> _attemptLogin() async {
    setState(() => _loading = true);
    try {
      // Use localHost for backend URL
      await ref.read(authProvider.notifier).loginWithHost(
            _emailController.text.trim(),
            _passwordController.text,
            localHost,
          );

      // On success navigate to main screen.
      if (mounted) Navigator.pushReplacementNamed(context, '/main');
    } catch (e) {
      final message = e is Exception ? e.toString() : 'Login failed';
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Login', style: TextStyle(fontSize: 32)),
              const SizedBox(height: 24),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _attemptLogin,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Login'),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.pushNamed(context, '/register');
                },
                child: const Text("Don't have an account? Register here"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
