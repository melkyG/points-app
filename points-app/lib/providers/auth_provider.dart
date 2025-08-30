import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:async' show StreamSubscription;

class User {
  final String uid;
  final String email;
  final String token;
  final String? accountName;

  User({required this.uid, required this.email, required this.token, this.accountName});

  Map<String, dynamic> toJson() => {'uid': uid, 'email': email, 'token': token, 'accountName': accountName};

  User copyWith({String? uid, String? email, String? token, String? accountName}) {
    return User(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      token: token ?? this.token,
      accountName: accountName ?? this.accountName,
    );
  }
}

class AuthNotifier extends StateNotifier<User?> {
  final _storage = const FlutterSecureStorage();
  Timer? _refreshTimer;
  bool _fetchingProfile = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;

  AuthNotifier() : super(null);

  /// Attempt to load user from secure storage. Call this at app startup.
  Future<void> tryLoadFromStorage() async {
    final token = await _storage.read(key: 'jwt');
    final email = await _storage.read(key: 'email');
    final uid = await _storage.read(key: 'uid');
    final account = await _storage.read(key: 'accountName');
    if (token != null && email != null && uid != null) {
      state = User(uid: uid, email: email, token: token, accountName: account);
  _scheduleRefreshIfNeeded(token);
  // start listening to Firestore profile updates
  _startProfileListener(uid);
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
  final accountName = data['accountName'] as String?;
  final refresh = data['refresh_token'] as String?;

      if (token == null || uid == null || userEmail == null) {
        throw Exception('Invalid response from auth server');
      }

  // Persist token and user info in secure storage.
  await _storage.write(key: 'jwt', value: token);
  if (refresh != null) await _storage.write(key: 'refresh_token', value: refresh);
  if (accountName != null) await _storage.write(key: 'accountName', value: accountName);
  await _storage.write(key: 'email', value: userEmail);
  await _storage.write(key: 'uid', value: uid);
  state = User(uid: uid, email: userEmail, token: token, accountName: accountName);
  _scheduleRefreshIfNeeded(token);
      // If accountName wasn't returned, fetch it async from backend
      if (accountName == null) {
        _fetchProfileIfNeeded(uid);
      }
  // start realtime listener for profile updates
  _startProfileListener(uid);
    } else if (resp.statusCode == 401) {
      final msg = resp.body.isNotEmpty ? resp.body : 'Unauthorized';
      throw Exception('Login failed: $msg');
    } else {
      throw Exception('Login failed: HTTP ${resp.statusCode}');
    }
  }

  /// Register a new user via backend /register. On success this does not
  /// log the user in; caller should navigate to LoginPage.
  Future<void> register(String email, String password, String accountName) async {
    final url = Uri.parse('http://127.0.0.1:8000/register');
    final resp = await http.post(url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email, 'password': password, 'accountName': accountName}));

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
  final accountName = data['accountName'] as String?;
        if (newToken == null || uid == null || email == null) {
          throw Exception('Invalid refresh response');
        }

        await _storage.write(key: 'jwt', value: newToken);
        if (accountName != null) await _storage.write(key: 'accountName', value: accountName);
        state = User(uid: uid, email: email, token: newToken, accountName: accountName);
        _scheduleRefreshIfNeeded(newToken);
        // If profile not present, fetch it async
        if (accountName == null) {
          _fetchProfileIfNeeded(uid);
        }
  // ensure realtime listener running
  _startProfileListener(uid);
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
  await _storage.delete(key: 'accountName');
    state = null;
  // cancel profile listener
  await _profileSub?.cancel();
  _profileSub = null;
  }

  /// Fetch user profile from backend /users/{uid} if not already fetching.
  Future<void> _fetchProfileIfNeeded(String uid) async {
    if (_fetchingProfile) return;
    _fetchingProfile = true;
    try {
      final uri = Uri.parse('http://127.0.0.1:8000/users/$uid');
      final resp = await http.get(uri);
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final accountName = data['accountName'] as String?;
        if (accountName != null) {
          await _storage.write(key: 'accountName', value: accountName);
          // Update state if still same user
          if (state != null && state!.uid == uid) {
            state = User(uid: state!.uid, email: state!.email, token: state!.token, accountName: accountName);
          }
        }
      } else {
        developer.log('Profile fetch returned ${resp.statusCode}');
      }
    } catch (e, st) {
      developer.log('Failed to fetch profile: $e\n$st');
    } finally {
      _fetchingProfile = false;
    }
  }

  Future<void> _startProfileListener(String uid) async {
    // cancel existing
    try {
      await _profileSub?.cancel();
    } catch (_) {}
    developer.log('AuthNotifier: starting profile listener for uid=$uid');
    try {
      // Ensure Firebase is initialized before subscribing.
      if (Firebase.apps.isEmpty) {
        developer.log('AuthNotifier: Firebase not initialized, awaiting Firebase.initializeApp()');
        try {
          await Firebase.initializeApp();
        } catch (e) {
          developer.log('AuthNotifier: Firebase.initializeApp() error (may already be initialized): $e');
        }
      }

      final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
      _profileSub = docRef.snapshots().listen((snapshot) async {
        final data = snapshot.data();
        developer.log('Firestore snapshot data for $uid: $data');
        if (data != null) {
          final accountName = data['accountName'] as String?;
          final email = data['email'] as String?;
          if (accountName != null) {
            await _storage.write(key: 'accountName', value: accountName);
          }
          if (email != null) {
            await _storage.write(key: 'email', value: email);
          }
          if (state != null && state!.uid == uid) {
            state = state!.copyWith(
              accountName: accountName ?? state!.accountName,
              email: email ?? state!.email,
            );
          }
        }
      }, onError: (e) {
        developer.log('Firestore listener error for uid=$uid: $e');
      });
      developer.log('AuthNotifier: profile listener subscribed for uid=$uid');
    } catch (e) {
      developer.log('AuthNotifier: failed to start profile listener for uid=$uid: $e');
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, User?>((ref) => AuthNotifier());
