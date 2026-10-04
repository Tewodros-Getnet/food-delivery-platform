# Splash Screen Unification Implementation Plan

## Problem Analysis

After investigating all three Flutter apps (customer, restaurant, rider), I found the issue causing different splash screen appearances:

**Current Problem:**
1. **Native Android Splash (before Flutter loads)**: White background (#FFFFFF) with logo
2. **Flutter Splash Screen (after Flutter loads)**: White background with logo in circle clip
3. **User sees transition between two different splash screens**

**Root Cause:**
- `flutter_native_splash` config in pubspec.yaml uses `color: "#FFFFFF"`
- Android `colors.xml` has `splash_background: #FFFFFF`
- Flutter `_SplashScreen` widget uses `backgroundColor: Colors.white`
- All are currently white instead of dark #0D0D0D

## Implementation Plan

- [ ] 1. Update flutter_native_splash configuration in all three pubspec.yaml files to use dark background.
      Change color from "#FFFFFF" to "#0D0D0D" and update android_12 configuration.
      Files: 
      - mobile/customer/pubspec.yaml
      - mobile/restaurant/pubspec.yaml  
      - mobile/rider/pubspec.yaml
      Verify: Check pubspec.yaml files contain the new color values.

- [ ] 2. Update Android colors.xml files to use dark splash background.
      Change splash_background color from "#FFFFFF" to "#0D0D0D".
      Files:
      - mobile/customer/android/app/src/main/res/values/colors.xml
      - mobile/restaurant/android/app/src/main/res/values/colors.xml
      - mobile/rider/android/app/src/main/res/values/colors.xml
      Verify: Check colors.xml files contain `<color name="splash_background">#0D0D0D</color>`.

- [ ] 3. Update Flutter _SplashScreen widgets to use dark background.
      Change backgroundColor from Colors.white to Color(0xFF0D0D0D).
      Files:
      - mobile/customer/lib/core/router/app_router.dart
      - mobile/restaurant/lib/core/router/app_router.dart
      - mobile/rider/lib/core/router/app_router.dart
      Verify: Check _SplashScreen widgets use `backgroundColor: Color(0xFF0D0D0D)`.

- [ ] 4. Regenerate native splash screens for customer app.
      Run flutter_native_splash:create to apply the new dark configuration.
      Files: Generated native splash resources in mobile/customer/android/app/src/main/res/
      Verify: Run `cd mobile/customer && dart run flutter_native_splash:create` and confirm no errors.

- [ ] 5. Regenerate native splash screens for restaurant app.
      Run flutter_native_splash:create to apply the new dark configuration.
      Files: Generated native splash resources in mobile/restaurant/android/app/src/main/res/
      Verify: Run `cd mobile/restaurant && dart run flutter_native_splash:create` and confirm no errors.

- [ ] 6. Regenerate native splash screens for rider app.
      Run flutter_native_splash:create to apply the new dark configuration.
      Files: Generated native splash resources in mobile/rider/android/app/src/main/res/
      Verify: Run `cd mobile/rider && dart run flutter_native_splash:create` and confirm no errors.

- [ ] 7. Test all three apps to ensure seamless splash screen transition.
      Build and run each app to verify both splash screens now have identical dark appearance.
      Files: N/A (testing step)
      Verify: Run `cd mobile/customer && flutter build apk` and similar for restaurant and rider apps. Install and launch to check splash screens match.

## Detailed Changes Required

### pubspec.yaml Changes (All 3 apps)
**Before:**
```yaml
flutter_native_splash:
  color: "#FFFFFF"
  image: "assets/images/logo.png"
  android_12:
    image: "assets/images/logo.png"
    icon_background_color: "#FFFFFF"
    color: "#FFFFFF"
```

**After:**
```yaml
flutter_native_splash:
  color: "#0D0D0D"
  image: "assets/images/logo.png"
  android_12:
    image: "assets/images/logo.png"
    icon_background_color: "#0D0D0D"
    color: "#0D0D0D"
```

### colors.xml Changes (All 3 apps)
**Before:**
```xml
<color name="splash_background">#FFFFFF</color>
```

**After:**
```xml
<color name="splash_background">#0D0D0D</color>
```

### app_router.dart Changes (All 3 apps)
**Before:**
```dart
return Scaffold(
  backgroundColor: Colors.white,
  body: Center(
    child: SizedBox(
      width: 180,
      height: 180,
      child: ClipOval(
        child: Image.asset(
          'assets/images/logo.png',
          fit: BoxFit.cover,
        ),
      ),
    ),
  ),
);
```

**After:**
```dart
return Scaffold(
  backgroundColor: Color(0xFF0D0D0D),
  body: Center(
    child: SizedBox(
      width: 180,
      height: 180,
      child: ClipOval(
        child: Image.asset(
          'assets/images/logo.png',
          fit: BoxFit.cover,
        ),
      ),
    ),
  ),
);
```

## Commands to Execute

1. **Customer App:**
   ```bash
   cd mobile/customer
   dart run flutter_native_splash:create
   ```

2. **Restaurant App:**
   ```bash
   cd mobile/restaurant  
   dart run flutter_native_splash:create
   ```

3. **Rider App:**
   ```bash
   cd mobile/rider
   dart run flutter_native_splash:create
   ```

## Expected Outcome

After implementing these changes:
- Both native Android splash (before Flutter loads) and Flutter splash (after Flutter loads) will have identical dark #0D0D0D background
- The logo will appear as a perfect circle in both splash screens
- Users will not see any transition between the two splash screens as they will be visually identical
- All three apps (customer, restaurant, rider) will have consistent splash screen behavior

## Why Two Splash Screens Are Needed

**Native Android Splash** (mandatory):
- Shows immediately when app icon is tapped, before Flutter engine loads
- Required by Android to prevent blank screen during app startup
- Generated by flutter_native_splash package
- Uses Android native resources (drawable, colors, themes)

**Flutter Splash Screen** (app-controlled):
- Shows after Flutter loads while app initializes (auth check, etc.)
- Controlled by Flutter router logic 
- Allows for programmatic control and smooth transitions to main app
- Uses Flutter widgets and Dart code

Both are necessary because Flutter apps have a cold start time where the Flutter engine must initialize before any Flutter widgets can be displayed.