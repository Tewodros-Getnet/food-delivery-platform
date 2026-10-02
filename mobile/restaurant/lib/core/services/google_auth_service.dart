import 'package:google_sign_in/google_sign_in.dart';
import 'package:dio/dio.dart';
import '../storage/secure_storage.dart';
import '../constants/api_constants.dart';
import '../../features/auth/models/user_model.dart';

class GoogleAuthService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'profile',
    ],
  );

  /// Sign in with Google and authenticate with backend
  static Future<UserModel?> signInWithGoogle() async {
    try {
      // Sign out first to force account selection
      await _googleSignIn.signOut();
      
      // Sign in with Google
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // User cancelled the sign-in
        return null;
      }

      // Get authentication details
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      
      if (googleAuth.idToken == null) {
        throw Exception('Failed to get ID token from Google');
      }

      // Send ID token to our backend using Dio
      final dio = Dio();
      final response = await dio.post(
        '${ApiConstants.baseUrl}${ApiConstants.googleSignIn}',
        data: {
          'idToken': googleAuth.idToken,
          'role': 'restaurant',
        },
      );

      if (response.statusCode == 200) {
        final data = response.data['data'] as Map<String, dynamic>;
        final tokens = data['tokens'] as Map<String, dynamic>;
        final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);

        // Store the token using secure storage
        final storage = SecureStorageService();
        await storage.saveTokens(
          jwt: tokens['jwt'] as String,
          refreshToken: tokens['refreshToken'] as String,
        );
        
        return user;
      } else {
        throw Exception('Failed to authenticate with backend');
      }
    } catch (e) {
      print('Google Sign-In Error: $e');
      await _googleSignIn.signOut(); // Clean up on error
      rethrow;
    }
  }

  /// Sign out from Google
  static Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      print('Google Sign-Out Error: $e');
    }
  }

  /// Check if currently signed in to Google
  static Future<bool> isSignedIn() async {
    return await _googleSignIn.isSignedIn();
  }

  /// Get current Google user (if signed in)
  static Future<GoogleSignInAccount?> getCurrentUser() async {
    return await _googleSignIn.signInSilently();
  }
}