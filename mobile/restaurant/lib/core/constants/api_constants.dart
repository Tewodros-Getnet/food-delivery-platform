class ApiConstants {
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
  static const String fcmToken = '/users/fcm-token';
  static const String restaurants = '/restaurants';
  static const String myRestaurant = '/restaurants/my';
  static const String myRestaurantStatus = '/restaurants/my/status';
  static const String myRestaurantRiders = '/restaurants/my/riders';
  static const String myRestaurantRidersInvite =
      '/restaurants/my/riders/invite';
  static const String menu = '/menu';
  static const String orders = '/orders';
  static const String myRestaurantAnalytics = '/restaurants/my/analytics';
}
