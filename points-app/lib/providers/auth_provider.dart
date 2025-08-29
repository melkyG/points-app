import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class User {
  final String uid;
  final String email;
  final String token;

  User({required this.uid, required this.email, required this.token});

  Map<String, dynamic> toJson() => {'uid': uid, 'email': email, 'token': token};
}

class AuthNotifier extends StateNotifier<User?> {
  final _storage = const FlutterSecureStorage();
  Timer? _refreshTimer;

  AuthNotifier() : super(null);

  /// Attempt to load user from secure storage. Call this at app startup.
  Future<void> tryLoadFromStorage() async {
    final token = await _storage.read(key: 'jwt');
    final email = await _storage.read(key: 'email');
    final uid = await _storage.read(key: 'uid');
    if (token != null && email != null && uid != null) {
      state = User(uid: uid, email: email, token: token);
  _scheduleRefreshIfNeeded(token);
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
  final refresh = data['refresh_token'] as String?;

      if (token == null || uid == null || userEmail == null) {
        throw Exception('Invalid response from auth server');
      }

  // Persist token and user info in secure storage.
  await _storage.write(key: 'jwt', value: token);
  if (refresh != null) await _storage.write(key: 'refresh_token', value: refresh);
  await _storage.write(key: 'email', value: userEmail);
  await _storage.write(key: 'uid', value: uid);

  state = User(uid: uid, email: userEmail, token: token);
  _scheduleRefreshIfNeeded(token);
    } else if (resp.statusCode == 401) {
      final msg = resp.body.isNotEmpty ? resp.body : 'Unauthorized';
      throw Exception('Login failed: $msg');
    } else {
      throw Exception('Login failed: HTTP ${resp.statusCode}');
    }
  }

  /// Register a new user via backend /register. On success this does not
  /// log the user in; caller should navigate to LoginPage.
  Future<void> register(String email, String password) async {
    final url = Uri.parse('http://127.0.0.1:8000/register');
    final resp = await http.post(url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email, 'password': password}));

    if (resp.statusCode == 200 || resp.statusCode == 201) {
      // Registration succeeded. Backend may return details in body.
      return;
    } else {
      String msg = 'Registration failed: HTTP ${resp.statusCode}';
      try {
        final body = json.decode(resp.body);
        if (body is Map && body['detail'] != null) msg = 'Registration failed: ${body['detail']}';
      } catch (_) {}
      throw Exception(msg);
    }
  }

  /// Decode JWT and return expiry (exp) as epoch seconds, or null.
  int? _parseJwtExpiry(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = parts[1];
      var normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final map = json.decode(decoded) as Map<String, dynamic>;
      return map['exp'] as int?;
    } catch (_) {
      return null;
    }
  }

  void _scheduleRefreshIfNeeded(String token) {
    // Cancel existing timer
    _refreshTimer?.cancel();

    final exp = _parseJwtExpiry(token);
    if (exp == null) return;

    final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    // Refresh 60 seconds before expiry
    final refreshAt = expiry.subtract(const Duration(seconds: 60));
    var delay = refreshAt.difference(DateTime.now());
    if (delay.isNegative) {
      // token already near/expired -> refresh immediately
      delay = const Duration(seconds: 0);
    }

    _refreshTimer = Timer(delay, () async {
      try {
        await refresh();
      } catch (_) {
        // refresh() handles logout on failure
      }
    });
  }

  /// Exchange refresh token for a new access token. On failure logs out.
  Future<void> refresh() async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken == null) {
      await logout();
      return;
    }

    try {
      final url = Uri.parse('http://127.0.0.1:8000/refresh');
      final resp = await http.post(url,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'refresh_token': refreshToken}));

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final newToken = data['access_token'] as String?;
        final uid = data['uid'] as String?;
        final email = data['email'] as String?;
        if (newToken == null || uid == null || email == null) {
          throw Exception('Invalid refresh response');
        }

        await _storage.write(key: 'jwt', value: newToken);
        state = User(uid: uid, email: email, token: newToken);
        _scheduleRefreshIfNeeded(newToken);
      } else {
        // Refresh failed - logout
        await logout();
      }
    } catch (e) {
      // On any error, logout to force re-auth
      await logout();
    }
  }

  Future<void> logout() async {
    // Attempt to call backend logout endpoint with refresh token if present
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken != null) {
      try {
        final url = Uri.parse('http://127.0.0.1:8000/auth/logout');
        await http.post(url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'refresh_token': refreshToken}));
      } catch (_) {
        // ignore errors during logout call
      }
    }
    _refreshTimer?.cancel();
    await _storage.delete(key: 'jwt');
    await _storage.delete(key: 'refresh_token');
    await _storage.delete(key: 'email');
    await _storage.delete(key: 'uid');
    state = null;
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, User?>((ref) => AuthNotifier());
