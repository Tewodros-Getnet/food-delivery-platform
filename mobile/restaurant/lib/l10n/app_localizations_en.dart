// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Food Delivery Restaurant';

  @override
  String get loading => 'Loading...';

  @override
  String get error => 'Error';

  @override
  String get errorOccurred => 'An error occurred';

  @override
  String get retry => 'Retry';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get logout => 'Logout';

  @override
  String get profile => 'Profile';

  @override
  String get orders => 'Orders';

  @override
  String get settings => 'Settings';

  @override
  String get language => 'Language';

  @override
  String get selectLanguage => 'Select Language';

  @override
  String get success => 'Language updated successfully';

  @override
  String get newOrders => 'New Orders';

  @override
  String get activeOrders => 'Active Orders';

  @override
  String get completedOrders => 'Completed Orders';

  @override
  String get cancelledOrders => 'Cancelled Orders';

  @override
  String get acceptOrder => 'Accept Order';

  @override
  String get declineOrder => 'Decline Order';

  @override
  String get markReady => 'Mark as Ready';

  @override
  String get markDelivered => 'Mark as Delivered';

  @override
  String get viewDetails => 'View Details';

  @override
  String get estimatedTime => 'Estimated Time';

  @override
  String get orderTotal => 'Order Total';

  @override
  String get updateStatus => 'Update Status';

  @override
  String get restaurantDashboard => 'Restaurant Dashboard';
}
