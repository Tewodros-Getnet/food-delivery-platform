import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';

enum AuthStatus { unknown, authenticated, unauthenticated, pendingVerification }

class AuthState {
  final AuthStatus status;
  final UserModel? user;
  final String? error;
  final bool isLoading;
  final String? pendingUserId;
  final String? devOtp;

  /// null  = not yet checked
  /// false = authenticated but no restaurant profile created
  /// true  = restaurant profile exists (any status)
  final bool? hasRestaurant;

  /// e.g. 'pending', 'approved', 'rejected' — from GET /restaurants/my
  final String? restaurantStatus;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.error,
    this.isLoading = false,
    this.pendingUserId,
    this.devOtp,
    this.hasRestaurant,
    this.restaurantStatus,
  });

  AuthState copyWith({
    AuthStatus? status,
    UserModel? user,
    String? error,
    bool? isLoading,
    String? pendingUserId,
    String? devOtp,
    bool? hasRestaurant,
    String? restaurantStatus,
  }) =>
      AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
        error: error,
        isLoading: isLoading ?? this.isLoading,
        pendingUserId: pendingUserId ?? this.pendingUserId,
        devOtp: devOtp ?? this.devOtp,
        hasRestaurant: hasRestaurant ?? this.hasRestaurant,
        restaurantStatus: restaurantStatus ?? this.restaurantStatus,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _svc;
  final DioClient _dio;

  AuthNotifier(this._svc, this._dio) : super(const AuthState()) {
    _check();
  }

  // ── Internal helpers ────────────────────────────────────────────────────────

  /// Checks JWT in storage, then fetches restaurant status if logged in.
  Future<void> _check() async {
    final ok = await _svc.isLoggedIn();
    if (!ok) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return;
    }
    state = state.copyWith(status: AuthStatus.authenticated);
    await _checkRestaurant();
  }

  /// Calls GET /restaurants/my to determine whether the user has a restaurant
  /// and what its approval status is. Sets hasRestaurant + restaurantStatus.
  /// On a 401 or 403 the account no longer exists or the token is invalid —
  /// log out immediately so the user isn't stuck in a broken authenticated state.
  Future<void> _checkRestaurant() async {
    try {
      final res = await _dio.dio.get(ApiConstants.myRestaurant);
      final data = res.data['data'] as Map<String, dynamic>?;
      state = state.copyWith(
        hasRestaurant: data != null,
        restaurantStatus: data?['status'] as String?,
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        // Token is invalid or the account was deleted by an admin.
        // Clear stored tokens so the next cold start shows the login screen,
        // then transition to unauthenticated — the router will redirect to /login.
        await _svc.logout();
        state = const AuthState(status: AuthStatus.unauthenticated);
        return;
      }
      if (code == 404) {
        // Authenticated but no restaurant profile created yet.
        state = state.copyWith(hasRestaurant: false, restaurantStatus: null);
        return;
      }
      // Network / timeout error — leave hasRestaurant null so the router waits
      // and the orders screen can show its own retry UI rather than redirecting.
    } catch (_) {
      state = state.copyWith(hasRestaurant: false);
    }
  }

  // ── Public methods ──────────────────────────────────────────────────────────

  Future<void> recheck() async {
    if (state.status != AuthStatus.authenticated) return;
    final still = await _svc.proactiveRefresh();
    if (!still) {
      await logout();
    } else {
      await _checkRestaurant();
    }
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await _svc.login(email: email, password: password);
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        isLoading: false,
      );
      // Fetch restaurant status right after login
      await _checkRestaurant();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString().replaceFirst('Exception: ', ''),
        status: AuthStatus.unauthenticated,
      );
    }
  }

  Future<void> register(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _svc.register(email: email, password: password);
      state = state.copyWith(
        status: AuthStatus.pendingVerification,
        pendingUserId: result.userId,
        devOtp: result.devOtp,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> verifyOtp(String code) async {
    final userId = state.pendingUserId;
    if (userId == null) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await _svc.verifyOtp(userId: userId, code: code);
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        isLoading: false,
        // New account always has no restaurant yet
        hasRestaurant: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString().replaceFirst('Exception: ', ''),
      );
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

  /// Called by RestaurantSetupScreen after a successful POST /restaurants.
  /// Marks the restaurant as created with 'pending' approval status so the
  /// router sends the user to the pending-approval screen instead of /orders.
  void onRestaurantCreated() {
    state = state.copyWith(
      hasRestaurant: true,
      restaurantStatus: 'pending',
    );
  }

  /// Called by PendingApprovalScreen when polling detects approval.
  void onRestaurantApproved() {
    state = state.copyWith(restaurantStatus: 'approved');
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(
    ref.read(authServiceProvider),
    ref.read(dioClientProvider),
  ),
);
