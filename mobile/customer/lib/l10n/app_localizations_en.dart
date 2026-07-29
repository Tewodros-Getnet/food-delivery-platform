// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Food Delivery';

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
  String get noOrders => 'No orders yet';

  @override
  String get trackOrder => 'Track Order';

  @override
  String get orderHistory => 'Order History';

  @override
  String get myAddress => 'My Address';

  @override
  String get addAddress => 'Add Address';

  @override
  String get editAddress => 'Edit Address';

  @override
  String get deleteAddress => 'Delete Address';

  @override
  String get selectAddress => 'Select Address';

  @override
  String get paymentMethod => 'Payment Method';

  @override
  String get totalPrice => 'Total Price';

  @override
  String get subtotal => 'Subtotal';

  @override
  String get deliveryFee => 'Delivery Fee';

  @override
  String get tax => 'Tax';

  @override
  String get congratulations => 'Congratulations!';

  @override
  String get orderPlaced => 'Order Placed Successfully';

  @override
  String get orderCancelled => 'Order Cancelled';

  @override
  String get deliveryAddress => 'Delivery Address';
}
