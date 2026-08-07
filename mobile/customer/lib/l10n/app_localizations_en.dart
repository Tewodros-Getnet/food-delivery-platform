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
  String get home => 'Home';

  @override
  String get orders => 'Orders';

  @override
  String get profile => 'Profile';

  @override
  String get alerts => 'Alerts';

  @override
  String get searchRestaurants => 'Search restaurants';

  @override
  String get searchDishes => 'Search dishes';

  @override
  String get deliveryTo => 'Deliver to';

  @override
  String get pickup => 'Pickup';

  @override
  String get delivery => 'Delivery';

  @override
  String get selectLocation => 'Select Location';

  @override
  String get reorder => 'Reorder';

  @override
  String get rate => 'Rate';

  @override
  String get reportProblem => 'Report a problem';

  @override
  String get cartEmpty => 'Your cart is empty';

  @override
  String get addItems => 'Add items to get started';

  @override
  String get checkout => 'Checkout';

  @override
  String get cart => 'Cart';

  @override
  String get continueShopping => 'Continue Shopping';

  @override
  String get total => 'Total';

  @override
  String get subtotal => 'Subtotal';

  @override
  String get deliveryFee => 'Delivery Fee';

  @override
  String get estimatedDelivery => 'Estimated Delivery';

  @override
  String get address => 'Address';

  @override
  String get selectAddress => 'Select Delivery Address';

  @override
  String get newAddress => 'Add New Address';

  @override
  String get paymentMethod => 'Payment Method';

  @override
  String get placeOrder => 'Place Order';

  @override
  String get orderPlaced => 'Order Placed!';

  @override
  String get orderNumber => 'Order #';

  @override
  String get trackOrder => 'Track Order';

  @override
  String get estimatedTime => 'Estimated Time';

  @override
  String get orderStatus => 'Order Status';

  @override
  String get myOrders => 'My Orders';

  @override
  String get noOrders => 'No orders yet';

  @override
  String get orderHistory => 'Order History';

  @override
  String get delivered => 'Delivered';

  @override
  String get cancelled => 'Cancelled';

  @override
  String get pending => 'Pending';

  @override
  String get confirmed => 'Confirmed';

  @override
  String get readyForPickup => 'Ready for Pickup';

  @override
  String get riderAssigned => 'Rider Assigned';

  @override
  String get pickedUp => 'Picked Up';

  @override
  String get paymentFailed => 'Payment Failed';

  @override
  String get pendingAcceptance => 'Pending Acceptance';

  @override
  String get pendingPayment => 'Pending Payment';

  @override
  String get restaurantName => 'Restaurant Name';

  @override
  String get cuisine => 'Cuisine';

  @override
  String get rating => 'Rating';

  @override
  String get reviews => 'Reviews';

  @override
  String get aboutRestaurant => 'About';

  @override
  String get menuItems => 'Menu';

  @override
  String get filterByCategory => 'Filter by Category';

  @override
  String get addToCart => 'Add to Cart';

  @override
  String get quantity => 'Quantity';

  @override
  String get specialInstructions => 'Special Instructions';

  @override
  String get modifiers => 'Customizations';

  @override
  String get saveAddress => 'Save Address';

  @override
  String get loginEmail => 'Email';

  @override
  String get loginPhone => 'Phone Number';

  @override
  String get loginPassword => 'Password';

  @override
  String get signup => 'Sign Up';

  @override
  String get login => 'Login';

  @override
  String get logout => 'Logout';

  @override
  String get forgotPassword => 'Forgot Password?';

  @override
  String get resetPassword => 'Reset Password';

  @override
  String get confirmPassword => 'Confirm Password';

  @override
  String get otp => 'OTP';

  @override
  String get verifyOtp => 'Verify OTP';

  @override
  String get resendOtp => 'Resend OTP';

  @override
  String get enterOtp => 'Enter OTP';

  @override
  String otpSentTo(Object phone) {
    return 'OTP sent to $phone';
  }

  @override
  String get accountSettings => 'Account Settings';

  @override
  String get editProfile => 'Edit Profile';

  @override
  String get displayName => 'Display Name';

  @override
  String get phoneNumber => 'Phone Number';

  @override
  String get email => 'Email';

  @override
  String get addresses => 'Saved Addresses';

  @override
  String get paymentMethods => 'Payment Methods';

  @override
  String get language => 'Language';

  @override
  String get selectLanguage => 'Select Language';

  @override
  String get darkMode => 'Dark Mode';

  @override
  String get notifications => 'Notifications';

  @override
  String get orderNotifications => 'Order Updates';

  @override
  String get promoNotifications => 'Promos & Offers';

  @override
  String get aboutApp => 'About App';

  @override
  String get version => 'Version';

  @override
  String get termsOfService => 'Terms of Service';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get contactUs => 'Contact Us';

  @override
  String get help => 'Help & Support';

  @override
  String get rateApp => 'Rate this App';

  @override
  String get settings => 'Settings';

  @override
  String get favoriteRestaurants => 'Favorites';

  @override
  String get addToFavorites => 'Add to Favorites';

  @override
  String get removeFromFavorites => 'Remove from Favorites';

  @override
  String get noFavorites => 'No favorite restaurants';

  @override
  String get error => 'Error';

  @override
  String get errorOccurred => 'An error occurred';

  @override
  String get success => 'Success';

  @override
  String get retry => 'Retry';

  @override
  String get close => 'Close';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get done => 'Done';

  @override
  String get loading => 'Loading...';

  @override
  String get networkError => 'Network error. Please check your connection.';

  @override
  String get tryAgain => 'Try Again';

  @override
  String get noInternet => 'No internet connection';

  @override
  String get serverError => 'Server error. Please try again later.';

  @override
  String get invalidEmail => 'Please enter a valid email';

  @override
  String get passwordTooShort => 'Password must be at least 6 characters';

  @override
  String get passwordMismatch => 'Passwords do not match';

  @override
  String get termsNotAccepted => 'Please accept the terms';

  @override
  String get unknownError => 'Something went wrong. Please try again.';

  @override
  String get ethCurrency => 'ETB';

  @override
  String failedToReorder(Object error) {
    return 'Failed to reorder: $error';
  }

  @override
  String get allItemsUnavailable =>
      'All items from this order are currently unavailable';

  @override
  String someItemsUnavailable(Object items) {
    return 'Some items are unavailable and were skipped: $items';
  }

  @override
  String get noItemsFound => 'No items found for this order';

  @override
  String get myAddress => 'My Address';

  @override
  String get addAddress => 'Add Address';

  @override
  String get editAddress => 'Edit Address';

  @override
  String get deleteAddress => 'Delete Address';

  @override
  String get totalPrice => 'Total Price';

  @override
  String get tax => 'Tax';

  @override
  String get congratulations => 'Congratulations!';

  @override
  String get orderCancelled => 'Order Cancelled';

  @override
  String get deliveryAddress => 'Delivery Address';

  @override
  String get all => 'All';

  @override
  String get searchFailed => 'Search failed. Please try again.';

  @override
  String get noResultsFor => 'No results for';

  @override
  String get closed => 'Closed';

  @override
  String get myProfile => 'My Profile';

  @override
  String get signOut => 'Sign Out';

  @override
  String get signOutConfirm => 'Are you sure you want to sign out?';

  @override
  String get saved => 'Saved';

  @override
  String get changePassword => 'Change Password';

  @override
  String get viewAllPastOrders => 'View all past orders';

  @override
  String get savedRestaurants => 'Saved Restaurants';

  @override
  String get yourFavouritePlaces => 'Your favourite places';

  @override
  String get manageDeliveryLocations => 'Manage delivery locations';

  @override
  String get offersAndRewards => 'Offers & Rewards';

  @override
  String get vouchersAndPromoCodes => 'Vouchers & Promo Codes';

  @override
  String get loyaltyPoints => 'Loyalty Points';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get support => 'Support';

  @override
  String get helpCenter => 'Help Center';

  @override
  String get faqsAndSupport => 'FAQs and support';

  @override
  String get reportProblemTitle => 'Report a Problem';

  @override
  String get about => 'About';

  @override
  String get appVersion => 'Version 1.0.0';

  @override
  String get account => 'Account';

  @override
  String get myActivity => 'My Activity';

  @override
  String get notSet => 'Not set';

  @override
  String get saveChanges => 'Save Changes';

  @override
  String get currentPassword => 'Current Password';

  @override
  String get newPasswordHint => 'New Password (min 8 chars)';

  @override
  String get updatePassword => 'Update Password';

  @override
  String get failedToLoadProfile => 'Failed to load profile';

  @override
  String get profilePhotoUpdated => 'Profile photo updated';

  @override
  String get profileUpdated => 'Profile updated';

  @override
  String get passwordUpdated => 'Password updated';

  @override
  String get photoUploadFailed => 'Failed to upload photo';

  @override
  String get browseRestaurants => 'Browse restaurants';

  @override
  String get clearCart => 'Clear Cart';

  @override
  String get clearCartConfirm => 'Remove all items from your cart?';

  @override
  String get clear => 'Clear';

  @override
  String subtotalWithCount(Object count) {
    return 'Subtotal ($count items)';
  }

  @override
  String get deliveryFeeNote => 'Calculated at checkout';

  @override
  String get proceedToCheckout => 'Proceed to Checkout';

  @override
  String get track => 'Track';

  @override
  String get adding => 'Adding...';

  @override
  String get orderSummary => 'Order Summary';

  @override
  String get waitingPayment => 'Waiting for payment confirmation...';

  @override
  String get checkPaymentStatus => 'Check payment status';

  @override
  String get payWithChapa => 'Pay with Chapa';

  @override
  String payWithChapaAmount(Object amount) {
    return 'Pay ETB $amount with Chapa';
  }

  @override
  String get selectDeliveryAddress => 'Please select a delivery address';

  @override
  String get noSavedAddresses => 'No saved addresses.';

  @override
  String get addDeliveryAddress => 'Add a delivery address →';

  @override
  String get paymentFailedRetry =>
      'Payment failed. Please try again or use a different method.';

  @override
  String get couldNotOpenPayment => 'Could not open payment page. Try again.';

  @override
  String get failedToLoadAddresses => 'Failed to load addresses';
}
