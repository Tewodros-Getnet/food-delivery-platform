import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';

class ResetPasswordState {
  final bool isLoading;
  final bool isSuccess;
  final String? error;

  const ResetPasswordState({
    this.isLoading = false,
    this.isSuccess = false,
    this.error,
  });

  ResetPasswordState copyWith({
    bool? isLoading,
    bool? isSuccess,
    String? error,
  }) {
    return ResetPasswordState(
      isLoading: isLoading ?? this.isLoading,
      isSuccess: isSuccess ?? this.isSuccess,
      error: error,
    );
  }
}

class ResetPasswordNotifier extends StateNotifier<ResetPasswordState> {
  final AuthService _authService;

  ResetPasswordNotifier(this._authService) : super(const ResetPasswordState());

  Future<void> resetPassword(String token, String newPassword) async {
    state = state.copyWith(isLoading: true, error: null, isSuccess: false);
    
    try {
      await _authService.resetPassword(token, newPassword);
      state = state.copyWith(isLoading: false, isSuccess: true);
    } catch (e) {
      state = state.copyWith(
        isLoading: false, 
        error: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  void reset() {
    state = const ResetPasswordState();
  }
}

final resetPasswordProvider = StateNotifierProvider<ResetPasswordNotifier, ResetPasswordState>((ref) {
  return ResetPasswordNotifier(ref.read(authServiceProvider));
});