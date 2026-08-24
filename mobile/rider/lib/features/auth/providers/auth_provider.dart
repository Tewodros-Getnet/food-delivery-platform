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
  /// true  = rider has accepted an invitation (part of a restaurant team)
  /// false = authenticated but not yet on any team
  final bool? hasAcceptedInvitation;

  /// Raw invitation payload from GET /riders/invitation or socket event.
  /// Non-null when there is a pending invitation waiting to be accepted.
  final Map<String, dynamic>? invitationData;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.error,
    this.isLoading = false,
    this.pendingUserId,
    this.devOtp,
    this.hasAcceptedInvitation,
    this.invitationData,
  });

  AuthState copyWith({
    AuthStatus? status,
    UserModel? user,
    String? error,
    bool? isLoading,
    String? pendingUserId,
    String? devOtp,
    bool? hasAcceptedInvitation,
    Map<String, dynamic>? invitationData,
    bool clearInvitation = false,
  }) =>
      AuthState(
        status:                status               ?? this.status,
        user:                  user                 ?? this.user,
        error:                 error,
        isLoading:             isLoading            ?? this.isLoading,
        pendingUserId:         pendingUserId        ?? this.pendingUserId,
        devOtp:                devOtp               ?? this.devOtp,
        hasAcceptedInvitation: hasAcceptedInvitation ?? this.hasAcceptedInvitation,
        invitationData:        clearInvitation ? null : (invitationData ?? this.invitationData),
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _svc;
  final DioClient   _dio;

  AuthNotifier(this._svc, this._dio) : super(const AuthState()) {
    _check();
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  Future<void> _check() async {
    final ok = await _svc.isLoggedIn();
    if (!ok) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return;
    }
    state = state.copyWith(status: AuthStatus.authenticated);
    await _checkInvitationStatus();
  }

  /// Fetches /riders/invitation to determine:
  ///  - Is there a pending invitation waiting to be accepted?
  ///  - Has the rider already accepted one (active team membership)?
  Future<void> _checkInvitationStatus() async {
    try {
      final res = await _dio.dio.get(ApiConstants.ridersInvitation);
      final data = res.data['data'] as Map<String, dynamic>?;

      if (data == null) {
        // No invitation and no team — rider is waiting
        state = state.copyWith(
          hasAcceptedInvitation: false,
          clearInvitation: true,
        );
        return;
      }

      final invStatus = data['status'] as String?;
      if (invStatus == 'accepted') {
        // Rider is already on a team — go straight to home
        state = state.copyWith(
          hasAcceptedInvitation: true,
          clearInvitation: true,
        );
      } else if (invStatus == 'pending') {
        // Pending invitation — show invitation screen
        state = state.copyWith(
          hasAcceptedInvitation: false,
          invitationData: data,
        );
      } else {
        state = state.copyWith(
          hasAcceptedInvitation: false,
          clearInvitation: true,
        );
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // No invitation record at all
        state = state.copyWith(
          hasAcceptedInvitation: false,
          clearInvitation: true,
        );
      }
      // Other network error — leave hasAcceptedInvitation null so router waits
    } catch (_) {
      state = state.copyWith(
        hasAcceptedInvitation: false,
        clearInvitation: true,
      );
    }
  }

  // ── Public methods ────────────────────────────────────────────────────────

  Future<void> recheck() async {
    if (state.status != AuthStatus.authenticated) return;
    final still = await _svc.proactiveRefresh();
    if (!still) {
      await logout();
    } else {
      await _checkInvitationStatus();
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
      await _checkInvitationStatus();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString().replaceFirst('Exception: ', ''),
        status: AuthStatus.unauthenticated,
      );
    }
  }

  Future<void> register(
    String email,
    String password, {
    String? displayName,
    String? phone,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _svc.register(
        email: email,
        password: password,
        displayName: displayName,
        phone: phone,
      );
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
        // New accounts have no invitation yet
        hasAcceptedInvitation: false,
        clearInvitation: true,
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

  // ── Invitation helpers (called by screens) ────────────────────────────────

  /// Called when a new invitation arrives (HTTP poll or WebSocket push).
  void onInvitationReceived(Map<String, dynamic> data) {
    state = state.copyWith(
      invitationData: data,
      hasAcceptedInvitation: false,
    );
  }

  /// Called after the rider taps "Accept" and the API responds OK.
  void onInvitationAccepted() {
    state = state.copyWith(
      hasAcceptedInvitation: true,
      clearInvitation: true,
    );
  }

  /// Called after the rider taps "Decline" and the API responds OK.
  void onInvitationDeclined() {
    state = state.copyWith(
      hasAcceptedInvitation: false,
      clearInvitation: true,
    );
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(
    ref.read(authServiceProvider),
    ref.read(dioClientProvider),
  ),
);
