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
  static const String ridersLocation = '/riders/location';
  static const String ridersAvailability = '/riders/availability';
  static const String ridersEarnings = '/riders/earnings';
  static const String ridersInvitation = '/riders/invitation';
  static const String deliveries = '/deliveries';
  static const String chat = '/chat';
}
