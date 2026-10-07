# Food Delivery Platform Analysis Report

## Executive Summary

The platform is a comprehensive food delivery system built with:
- **Backend**: Node.js/Express/TypeScript with PostgreSQL database
- **Mobile Apps**: 3 Flutter apps (Customer, Restaurant, Rider) using Flutter 3.0+
- **Admin**: Next.js 14 React application
- **Architecture**: REST APIs with Socket.IO for real-time features
- **Database**: PostgreSQL with proper migrations and full geolocation support
- **Infrastructure**: Deployed on Render.com with Cloudinary for image storage

## Dependency Inventory

### Customer App (`mobile/customer/pubspec.yaml`)
```yaml
# Core Dependencies
flutter_riverpod: ^2.4.9        # State management
dio: ^5.4.0                      # HTTP client
flutter_secure_storage: ^9.2.2  # Token storage
go_router: ^13.0.1              # Navigation

# Map & Location
flutter_map: ^6.1.0             # Map widget
latlong2: ^0.9.0                # Lat/lng coordinates
geolocator: ^11.0.0             # GPS positioning

# Firebase & Social
firebase_core: ^2.24.2
firebase_messaging: ^14.7.10    # Push notifications
google_sign_in: ^6.2.1

# UI & Media
cached_network_image: ^3.3.1
image_picker: ^1.0.7
socket_io_client: ^2.0.3+1      # Real-time features
```

### Restaurant App (`mobile/restaurant/pubspec.yaml`)
```yaml
flutter_map: ^8.3.0             # Newer map version
geolocator: ^14.0.2             # Newer geolocator version
# (Same core dependencies as customer app)
```

### Rider App (`mobile/rider/pubspec.yaml`)
```yaml
flutter_map: ^6.1.0             # Same as customer
latlong2: ^0.9.0
geolocator: ^11.0.0
# (Same core dependencies as customer app)
```

### Backend (`backend/package.json`)
```json
{
  "express": "^4.18.2",
  "pg": "^8.11.3",
  "node-pg-migrate": "^6.2.2",
  "socket.io": "^4.7.2",
  "cloudinary": "^2.0.0",
  "firebase-admin": "^12.0.0",
  "jsonwebtoken": "^9.0.2"
}
```

## Map Infrastructure

### Map Library: Flutter Map
The platform uses **flutter_map** with OpenStreetMap tiles:

**Tile Provider Configuration** (from `mobile/customer/lib/features/profile/screens/map_picker_screen.dart`):
```dart
TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: 'com.fooddelivery.customer',
)
```

### Current Map Implementations

1. **Address Picker** (`features/profile/screens/map_picker_screen.dart`)
   - User can pick delivery location
   - GPS auto-location with fallback to manual tap
   - Pin-drop interface with address form

2. **Order Tracking** (`features/orders/screens/order_tracking_screen.dart`)
   - Real-time rider tracking
   - Shows rider, restaurant, and customer markers
   - Polyline from rider to destination
   - Updates via Socket.IO

3. **Rider Delivery** (`mobile/rider/lib/features/delivery/screens/home_screen.dart`)
   - Live delivery map with navigation
   - Restaurant and customer markers
   - Rider's current position

### Map Component Patterns
```dart
// Standard FlutterMap setup used across the platform
FlutterMap(
  mapController: _mapController,
  options: MapOptions(
    initialCenter: LatLng(latitude, longitude),
    initialZoom: 14,
    onTap: _onMapTap, // For interactive maps
  ),
  children: [
    TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.fooddelivery.[app_name]',
    ),
    MarkerLayer(
      markers: [
        Marker(
          point: LatLng(lat, lng),
          width: 48,
          height: 48,
          child: Icon(Icons.location_pin, color: Colors.red, size: 48),
        ),
      ],
    ),
  ],
)
```

## Restaurant Data Model

### Backend Schema (`backend/src/models/restaurant.model.ts`)
```typescript
interface Restaurant {
  id: string;
  owner_id: string;
  name: string;
  description: string | null;
  logo_url: string | null;
  cover_image_url: string | null;
  address: string;
  latitude: number;           // ✓ PRESENT
  longitude: number;          // ✓ PRESENT
  category: string | null;
  status: RestaurantStatus;   // 'pending' | 'approved' | 'rejected' | 'suspended'
  average_rating: number;
  is_open?: boolean;
  operating_hours?: Record<string, { open: string; close: string }> | null;
  minimum_order_value?: number;
  promo_banner_text?: string | null;
  promo_banner_image_url?: string | null;
  rejection_reason?: string | null;
  created_at: Date;
  updated_at: Date;
}
```

### Flutter Model (`mobile/customer/lib/features/restaurants/models/restaurant_model.dart`)
```dart
class RestaurantModel {
  final String id;
  final String name;
  final String? description;
  final String? logoUrl;
  final String? coverImageUrl;
  final String address;
  final double latitude;      // ✓ PRESENT
  final double longitude;     // ✓ PRESENT
  final String? category;
  final double averageRating;
  final bool isOpen;
  final Map<String, dynamic>? operatingHours;
  final String? promoBannerText;
  final String? promoBannerImageUrl;
  final double? minimumOrderValue;
  
  // Factory constructor parses from JSON API response
  factory RestaurantModel.fromJson(Map<String, dynamic> json) => ...
}
```

**✅ GEOLOCATION CONFIRMED**: Both backend database and Flutter models have `latitude`/`longitude` fields.

## API Endpoints Reference

### Restaurant Endpoints (`backend/src/routes/restaurants.ts`)

| Method | Path | Auth | Description | Response Shape |
|--------|------|------|-------------|----------------|
| `GET` | `/restaurants` | None | List approved restaurants | `{ restaurants: Restaurant[], total: number }` |
| `GET` | `/restaurants/:id` | None | Get restaurant details | `Restaurant` |
| `GET` | `/restaurants/:id/menu` | None | Get restaurant menu | `MenuItemModel[]` |
| `GET` | `/restaurants/:id/ratings` | None | Get restaurant reviews | `Rating[]` |
| `POST` | `/restaurants` | Restaurant | Create restaurant | `Restaurant` |
| `PUT` | `/restaurants/my/status` | Restaurant | Toggle open/closed | `Restaurant` |
| `PUT` | `/restaurants/my/hours` | Restaurant | Set operating hours | `Restaurant` |
| `PUT` | `/restaurants/my/images` | Restaurant | Upload logo/cover | `Restaurant` |

### Restaurant Service (`mobile/customer/lib/features/restaurants/services/restaurant_service.dart`)
```dart
class RestaurantService {
  // GET /restaurants?category=...
  Future<List<RestaurantModel>> getRestaurants({String? category});
  
  // GET /restaurants/:id
  Future<RestaurantModel> getById(String id);
  
  // GET /restaurants/:id/menu  
  Future<List<MenuItemModel>> getMenu(String restaurantId);
  
  // GET /search?q=...
  Future<Map<String, dynamic>> search(String q);
  
  // GET /restaurants/:id/ratings
  Future<List<Map<String, dynamic>>> getRestaurantRatings(String restaurantId);
}
```

**Key Finding**: The `/restaurants` endpoint currently supports category filtering but **no geolocation filtering**. For the map feature, we'll need to either:
1. Add radius/bounding-box filtering to this endpoint, OR
2. Fetch all restaurants and filter client-side (acceptable for moderate datasets)

## Customer App Architecture

### Router Setup (`core/router/app_router.dart`)
Uses **GoRouter** with **StatefulShellRoute** for bottom navigation:

```dart
StatefulShellRoute.indexedStack(
  branches: [
    StatefulShellBranch(routes: [
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
    ]),
    StatefulShellBranch(routes: [
      GoRoute(path: '/orders', builder: (_, __) => const OrderHistoryScreen()),
    ]),
    StatefulShellBranch(routes: [
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
    ]),
    StatefulShellBranch(routes: [
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
    ]),
  ],
)
```

### Feature Folder Structure
```
lib/
├── core/
│   ├── network/dio_client.dart     # HTTP client with auto token refresh
│   ├── router/app_router.dart      # GoRouter configuration
│   ├── providers/theme_provider.dart
│   └── constants/api_constants.dart
├── features/
│   ├── auth/                       # Login, register, OTP
│   ├── cart/                       # Shopping cart state
│   ├── home/                       # Restaurant browsing & search
│   ├── restaurants/                # Restaurant detail, favorites
│   ├── orders/                     # Checkout, tracking, history
│   ├── profile/                    # User profile, addresses
│   └── notifications/              # Push notification handling
```

### State Management: Riverpod
```dart
// Pattern used throughout the app
final restaurantsProvider = FutureProvider<List<RestaurantModel>>(
  (ref) => ref.read(restaurantServiceProvider).getRestaurants()
);

// In widget:
final restaurants = ref.watch(restaurantsProvider);
restaurants.when(
  loading: () => CircularProgressIndicator(),
  error: (e, _) => RetryWidget(error: e, onRetry: () => ref.refresh(restaurantsProvider)),
  data: (list) => ListView.builder(...),
)
```

### API Client Setup (`core/network/dio_client.dart`)
- **Base URL**: `https://food-delivery-platform-i5by.onrender.com/api/v1`
- **Auto token refresh**: 401 responses trigger refresh token flow
- **Session expiry**: Emits stream event for app-wide logout
- **Timeouts**: 120 seconds connect/receive

## Existing Restaurant Flow

### Home Screen (`features/home/screens/home_screen.dart`)
**Current Layout**:
1. **SliverAppBar** with search bar (floating, snaps on scroll)
2. **Category filter chips** (All, plus extracted from restaurant.category)
3. **Restaurant cards** in a scrollable list

**Search Functionality**:
- Debounced text input (400ms delay)
- Calls `/search?q=...` API endpoint
- Returns both restaurants and menu items
- Shows separate sections for each result type

**Restaurant Card Features**:
- Cover image with fallback gradient placeholder
- Restaurant logo, name, rating, category
- Open/closed status indicator
- Favorite toggle (requires authentication)
- Tap navigates to `/restaurant/:id` detail page

### Restaurant Detail Flow
1. **Home** → Restaurant card tap → **Restaurant Detail** (`/restaurant/:id`)
2. **Detail** shows menu, allows adding items to cart
3. **Cart** → **Checkout** → **Order Tracking**

## Authentication Patterns

### Auth States (`features/auth/providers/auth_provider.dart`)
```dart
enum AuthStatus {
  unknown,           // Initial/loading state
  authenticated,     // Logged in user
  unauthenticated,   // Not logged in
  pendingVerification, // Registered but awaiting OTP
  guest              // Browse-only mode (no ordering)
}
```

### Token Storage
- **JWT**: `flutter_secure_storage` with key `'jwt'`
- **Refresh Token**: Stored with key `'refreshToken'`
- **Auto-refresh**: Built into Dio interceptor

### Guest Access Implementation
```dart
// Router redirect logic (core/router/app_router.dart)
case AuthStatus.guest:
  if (isProtected) return '/landing';  // Block protected screens
  return null;                        // Allow home/browsing

// Bottom nav behavior (core/router/app_router.dart)
onDestinationSelected: (index) {
  if (isGuest && index > 0) {
    GoRouter.of(context).go('/landing'); // Redirect to login
    return;
  }
  // ... normal navigation
}
```

**Key Finding**: Guest users can browse the home screen but are redirected to login when accessing protected tabs (Orders, Notifications, Profile). This is perfect for our map feature.

## UI Component Patterns

### Theme Configuration (`main.dart`)
```dart
ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.orange,     // Primary brand color
    brightness: Brightness.light,
  ),
  useMaterial3: true,
  appBarTheme: AppBarTheme(
    backgroundColor: Colors.transparent,
    foregroundColor: Colors.black87,
    elevation: 0,
    scrolledUnderElevation: 2,
  ),
)
```

### Card Pattern (from home screen)
```dart
Card(
  margin: EdgeInsets.only(bottom: 14),
  clipBehavior: Clip.antiAlias,
  elevation: 2,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  child: InkWell(onTap: () => context.push('/restaurant/$id')),
)
```

### Navigation Pattern
- **Push**: `context.push('/restaurant/$id')` for detail screens
- **Go**: `context.go('/landing')` for tab/route replacement
- **Parameters**: Path parameters and `extra` object for data passing

### Loading States
- **FutureProvider**: `restaurants.when(loading:, error:, data:)`
- **Manual loading**: `CircularProgressIndicator` with `isLoading` state
- **Retry pattern**: `RetryWidget` with onRetry callback

## Integration Points for Map Feature

### 1. Navigation Integration
**Recommended Placement**: Add a 5th tab to the bottom navigation

**Current Navigation** (`core/router/app_router.dart`):
```dart
destinations: [
  NavigationDestination(label: 'Home', icon: Icons.home_outlined),
  NavigationDestination(label: 'Orders', icon: Icons.receipt_long_outlined),
  NavigationDestination(label: 'Alerts', icon: Icons.notifications_outlined),
  NavigationDestination(label: 'Profile', icon: Icons.person_outline),
]
```

**Proposed Addition**:
```dart
destinations: [
  NavigationDestination(label: 'Home', icon: Icons.home_outlined),
  NavigationDestination(label: 'Map', icon: Icons.map_outlined),        // NEW
  NavigationDestination(label: 'Orders', icon: Icons.receipt_long_outlined),
  NavigationDestination(label: 'Alerts', icon: Icons.notifications_outlined),
  NavigationDestination(label: 'Profile', icon: Icons.person_outline),
]
```

### 2. Route Registration
**Add to StatefulShellRoute branches**:
```dart
StatefulShellBranch(routes: [
  GoRoute(
    path: '/map',
    builder: (_, __) => const RestaurantMapScreen(),
  ),
]),
```

### 3. Provider Integration
**New Providers Needed**:
```dart
// Get all restaurants for map display
final mapRestaurantsProvider = FutureProvider<List<RestaurantModel>>(
  (ref) => ref.read(restaurantServiceProvider).getRestaurants()
);

// User location for map centering
final userLocationProvider = FutureProvider<LatLng>(
  (ref) => _getCurrentLocation()
);
```

### 4. Restaurant Service Extension
**No changes needed** - existing `getRestaurants()` method returns all approved restaurants with lat/lng data.

## Recommended Implementation Plan

### Phase 1: Map Screen Foundation
1. **Create RestaurantMapScreen** (`features/restaurants/screens/restaurant_map_screen.dart`)
   - Copy FlutterMap setup from existing map_picker_screen.dart
   - Use OpenStreetMap tiles with customer userAgent
   - Center on user location (Addis Ababa fallback: `9.0192, 38.7525`)
   - Add GPS recentering FAB (copy from map_picker_screen.dart)

2. **Add Map Tab to Bottom Navigation**
   - Update `core/router/app_router.dart` StatefulShellRoute
   - Add NavigationDestination with `Icons.map_outlined`
   - Position as 2nd tab (Home, Map, Orders, Alerts, Profile)

3. **Implement Restaurant Markers**
   - Fetch restaurants using existing `restaurantsProvider`
   - Create markers with restaurant icon + name labels
   - Handle loading/error states using established patterns

### Phase 2: Marker Interaction
4. **Add Marker Tap Navigation**
   - Implement marker `onTap` to navigate to `/restaurant/:id`
   - Use existing navigation pattern: `context.push('/restaurant/$id')`
   - Reuse existing restaurant detail screen (no changes needed)

5. **Custom Marker Design**
   - Restaurant icon: `Icons.restaurant` or `Icons.store`
   - Color coding: Green (open), Red (closed), based on `restaurant.isOpen`
   - Name label below marker (similar to Google Maps style)

### Phase 3: Access Control & UX
6. **Guest Access Support**
   - Map screen accessible to both authenticated and guest users
   - No authentication checks needed (follows home screen pattern)
   - Guest users can browse map and view restaurant details

7. **Performance Optimization**
   - Marker clustering if restaurant count > 50
   - Viewport-based filtering for large datasets
   - Cached network images for restaurant logos (if displayed on markers)

### Phase 4: Polish & Integration
8. **Visual Polish**
   - Follow existing Material 3 theme (Colors.orange primary)
   - Match card styling from home screen for any overlays
   - Consistent loading/error handling with RetryWidget

9. **State Management Integration**
   - Use existing Riverpod patterns
   - Integrate with favorites system (show favorite status on markers)
   - Respect category filtering (add category filter to map)

## File Structure for Implementation

```
mobile/customer/lib/features/restaurants/screens/
├── restaurant_detail_screen.dart          # ✓ Exists
├── favorites_screen.dart                  # ✓ Exists  
└── restaurant_map_screen.dart             # 📝 NEW

mobile/customer/lib/core/router/
└── app_router.dart                        # 📝 Modify (add map route)
```

## Risks & Constraints

### Missing Data: None
- ✅ Restaurant lat/lng fields exist in database and models
- ✅ Map libraries already integrated and functioning  
- ✅ API endpoints provide all necessary data

### Performance Considerations
- **Restaurant Count**: Current deployment likely has <100 restaurants - no clustering needed initially
- **Map Tiles**: OpenStreetMap is free but rate-limited - acceptable for moderate usage
- **Real-time Updates**: No need for live restaurant status on map - periodic refresh is sufficient

### Breaking Change Risks: Minimal
- **Navigation Changes**: Adding a 5th tab shifts tab indices - existing deep links remain unaffected
- **API Changes**: No backend modifications required
- **State Management**: New providers don't conflict with existing ones

### Implementation Constraints
- **Location Permissions**: Must handle GPS permission gracefully (copy from map_picker_screen.dart)
- **Network Handling**: Must handle restaurant fetch failures with retry mechanism
- **Platform Consistency**: Should match existing map styling used in rider/restaurant apps

## Success Criteria

1. **Functional Requirements**
   - ✅ Map displays restaurant locations as markers with names
   - ✅ Tapping marker navigates to restaurant detail page
   - ✅ Accessible to both authenticated and guest users
   - ✅ GPS location with manual fallback
   - ✅ Loading/error states handled gracefully

2. **UX Requirements**
   - ✅ Consistent with existing app design (Material 3, orange theme)
   - ✅ Performance comparable to existing screens
   - ✅ Intuitive navigation (5th tab in bottom nav)

3. **Technical Requirements**
   - ✅ Uses existing architecture patterns (Riverpod, GoRouter, Dio)
   - ✅ No breaking changes to existing functionality
   - ✅ Follows established code organization and styling

This analysis confirms the platform is well-architected for adding the restaurant map discovery feature with minimal risk and effort. All necessary data and infrastructure already exists.