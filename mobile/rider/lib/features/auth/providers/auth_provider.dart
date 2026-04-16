import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated, pendingVerification }

class AuthState {
  final AuthStatus status;
  final UserModel? user;
  final String? error;
  final bool isLoading;
  final String? pendingUserId;
  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.error,
    this.isLoading = false,
    this.pendingUserId,
  });
  AuthState copyWith({
    AuthStatus? status,
    UserModel? user,
    String? error,
    bool? isLoading,
    String? pendingUserId,
  }) =>
      AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
        error: error,
        isLoading: isLoading ?? this.isLoading,
        pendingUserId: pendingUserId ?? this.pendingUserId,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _svc;
  AuthNotifier(this._svc) : super(const AuthState()) {
    _check();
  }

  Future<void> _check() async {
    final ok = await _svc.isLoggedIn();
    state = state.copyWith(
      status: ok ? AuthStatus.authenticated : AuthStatus.unauthenticated,
    );
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await _svc.login(email: email, password: password);
      state = state.copyWith(
          status: AuthStatus.authenticated, user: user, isLoading: false);
    } catch (e) {
      state = state.copyWith(
          isLoading: false,
          error: e.toString(),
          status: AuthStatus.unauthenticated);
    }
  }

  Future<void> register(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final userId = await _svc.register(email: email, password: password);
      state = state.copyWith(
          status: AuthStatus.pendingVerification,
          pendingUserId: userId,
          isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> verifyOtp(String code) async {
    final userId = state.pendingUserId;
    if (userId == null) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await _svc.verifyOtp(userId: userId, code: code);
      state = state.copyWith(
          status: AuthStatus.authenticated, user: user, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> resendOtp() async {
    final userId = state.pendingUserId;
    if (userId == null) return;
    await _svc.resendOtp(userId: userId);
  }

  Future<void> logout() async {
    await _svc.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ref.read(authServiceProvider)),
);
