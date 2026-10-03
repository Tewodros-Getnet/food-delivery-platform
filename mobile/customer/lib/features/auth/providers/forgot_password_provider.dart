import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';

class ForgotPasswordState {
  final bool isLoading;
  final bool isSuccess;
  final String? error;

  const ForgotPasswordState({
    this.isLoading = false,
    this.isSuccess = false,
    this.error,
  });

  ForgotPasswordState copyWith({
    bool? isLoading,
    bool? isSuccess,
    String? error,
  }) {
    return ForgotPasswordState(
      isLoading: isLoading ?? this.isLoading,
      isSuccess: isSuccess ?? this.isSuccess,
      error: error,
    );
  }
}

class ForgotPasswordNotifier extends StateNotifier<ForgotPasswordState> {
  final AuthService _authService;

  ForgotPasswordNotifier(this._authService) : super(const ForgotPasswordState());

  Future<void> requestReset(String email) async {
    state = state.copyWith(isLoading: true, error: null, isSuccess: false);
    
    try {
      await _authService.requestPasswordReset(email);
      state = state.copyWith(isLoading: false, isSuccess: true);
    } catch (e) {
      state = state.copyWith(
        isLoading: false, 
        error: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  void reset() {
    state = const ForgotPasswordState();
  }
}

final forgotPasswordProvider = StateNotifierProvider<ForgotPasswordNotifier, ForgotPasswordState>((ref) {
  return ForgotPasswordNotifier(ref.read(authServiceProvider));
});