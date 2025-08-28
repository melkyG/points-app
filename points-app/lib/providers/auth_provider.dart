import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class User {
  final String uid;
  final String email;
  final String token;

  User({required this.uid, required this.email, required this.token});

  Map<String, dynamic> toJson() => {'uid': uid, 'email': email, 'token': token};
}

class AuthNotifier extends StateNotifier<User?> {
  AuthNotifier() : super(null) {
    _loadFromStorage();
  }

  Future<void> _loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt');
    final email = prefs.getString('email');
    final uid = prefs.getString('uid');
    if (token != null && email != null && uid != null) {
      state = User(uid: uid, email: email, token: token);
    }
  }

  /// Attempts login against the FastAPI backend. Throws an exception on failure.
  Future<void> login(String email, String password) async {
    final url = Uri.parse('http://127.0.0.1:8000/login');
    final resp = await http.post(url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email, 'password': password}));

    if (resp.statusCode == 200) {
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final token = data['access_token'] as String?;
      final uid = data['uid'] as String?;
      final userEmail = data['email'] as String?;

      if (token == null || uid == null || userEmail == null) {
        throw Exception('Invalid response from auth server');
      }

      // Persist token and user info locally. For production use flutter_secure_storage.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jwt', token);
      await prefs.setString('email', userEmail);
      await prefs.setString('uid', uid);

      state = User(uid: uid, email: userEmail, token: token);
    } else if (resp.statusCode == 401) {
      final msg = resp.body.isNotEmpty ? resp.body : 'Unauthorized';
      throw Exception('Login failed: $msg');
    } else {
      throw Exception('Login failed: HTTP ${resp.statusCode}');
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt');
    await prefs.remove('email');
    await prefs.remove('uid');
    state = null;
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, User?>((ref) => AuthNotifier());
