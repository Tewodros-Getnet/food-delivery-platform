class ApiConstants {
  // Change to your Render backend URL when deployed
  // e.g. 'https://your-app.onrender.com/api/v1'
  static const String baseUrl =
      'https://food-delivery-platform-i5by.onrender.com/api/v1';
  static const String wsUrl =
      'https://food-delivery-platform-i5by.onrender.com';

  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String refresh = '/auth/refresh';
  static const String logout = '/auth/logout';
  static const String verifyOtp = '/auth/verify-otp';
  static const String resendOtp = '/auth/resend-otp';
  static const String profile = '/users/profile';
  static const String password = '/users/password';
  static const String addresses = '/users/addresses';
  static const String fcmToken = '/users/fcm-token';
  static const String restaurants = '/restaurants';
  static const String search = '/search';
  static const String orders = '/orders';
  static const String estimateFee = '/payments/estimate-fee';
  static const String disputes = '/disputes';
}
