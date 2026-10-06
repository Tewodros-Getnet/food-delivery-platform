# Flutter Apps Splash & Icon Fix Plan

## Investigation Findings

### Issue 1: Launch Background XML Files
**Customer App**: Uses incorrect `@android:color/white` reference instead of solid color
**Restaurant App**: Correctly uses `@color/splash_background` 
**Rider App**: Correctly uses `@color/splash_background`

### Issue 2: Colors.xml Configuration
**Customer App**: Missing `splash_background` color definition (only has `ic_launcher_background`)
**Restaurant App**: Correctly defines `splash_background` as #0D0D0D
**Rider App**: Correctly defines `splash_background` as #0D0D0D

### Issue 3: Background.png Files Still Present
**Restaurant App**: Has background.png in drawable/ and drawable-v21/ directories
**Rider App**: Has background.png in drawable/ and drawable-v21/ directories
**Customer App**: No background.png files found (correctly cleaned up)

### Issue 4: Customer App Icon Offset
**Root Cause**: The source logo asset (mobile/customer/assets/images/logo.png) has uneven padding with excessive white/transparent space on the right side of the image
**Impact**: This causes the adaptive icon foreground to appear offset to the right
**Configuration**: Customer app pubspec.yaml uses white background (#FFFFFF) while restaurant/rider use black (#0D0D0D)

### Issue 5: Root Directory Unused Assets
**Found**: customer.png, restaurant.png, rider.png in c:\food-delivery-platform-main\assets\
**Status**: Not referenced in any pubspec.yaml files or build configurations - safe to delete

## Step-by-Step Fix Plan

### 1. Fix Customer App Launch Background XML
- **What**: Update launch_background.xml to use proper color reference and add missing color definition
- **Files to modify**:
  - `c:\food-delivery-platform-main\mobile\customer\android\app\src\main\res\drawable\launch_background.xml`
  - `c:\food-delivery-platform-main\mobile\customer\android\app\src\main\res\values\colors.xml`
- **Changes**:
  - Replace `@android:color/white` with `@color/splash_background` in launch_background.xml
  - Add `<color name="splash_background">#0D0D0D</color>` to colors.xml
- **Verify**: Run `flutter clean && flutter build apk` for customer app - should build without drawable reference errors

### 2. Remove Residual Background.png Files
- **What**: Delete leftover background.png files from restaurant and rider apps
- **Files to delete**:
  - `c:\food-delivery-platform-main\mobile\restaurant\android\app\src\main\res\drawable\background.png`
  - `c:\food-delivery-platform-main\mobile\restaurant\android\app\src\main\res\drawable-v21\background.png`
  - `c:\food-delivery-platform-main\mobile\rider\android\app\src\main\res\drawable\background.png`
  - `c:\food-delivery-platform-main\mobile\rider\android\app\src\main\res\drawable-v21\background.png`
- **Verify**: Run `flutter clean && flutter build apk` for both apps - should build without referencing deleted bitmap files

### 3. Fix Customer App Icon Centering
- **What**: Update customer app to use consistent black adaptive icon background and ensure proper icon generation
- **Files to modify**:
  - `c:\food-delivery-platform-main\mobile\customer\pubspec.yaml`
- **Changes**:
  - Change `adaptive_icon_background` from "#FFFFFF" to "#0D0D0D" to match other apps
  - Add `remove_alpha_channel: true` to ensure clean icon generation
- **Note**: The source logo asset has uneven padding, but changing to black background will make the offset less visible
- **Verify**: Run `flutter packages pub run flutter_launcher_icons:main` then build APK - icon should appear more centered

### 4. Clean Up Root Directory Assets
- **What**: Remove unused PNG files from root assets directory
- **Files to delete**:
  - `c:\food-delivery-platform-main\assets\customer.png`
  - `c:\food-delivery-platform-main\assets\restaurant.png`
  - `c:\food-delivery-platform-main\assets\rider.png`
- **Verify**: Search codebase to confirm no references exist, then delete files

### 5. Regenerate Native Splash Screens (Optional Cleanup)
- **What**: Re-run native splash generation to ensure clean state after background.png removal
- **Commands to run**:
  - `cd c:\food-delivery-platform-main\mobile\restaurant && flutter packages pub run flutter_native_splash:create`
  - `cd c:\food-delivery-platform-main\mobile\rider && flutter packages pub run flutter_native_splash:create`
- **Verify**: Check that no new background.png files are created and splash screens still work correctly

## Drawable Directory Paths Reference
All three apps have identical drawable directory structures:
- drawable/
- drawable-hdpi/
- drawable-mdpi/  
- drawable-night-hdpi/
- drawable-night-mdpi/
- drawable-night-xhdpi/
- drawable-night-xxhdpi/
- drawable-night-xxxhdpi/
- drawable-v21/
- drawable-xhdpi/
- drawable-xxhdpi/
- drawable-xxxhdpi/

Only restaurant and rider apps have residual background.png files in drawable/ and drawable-v21/ subdirectories.

## Build Commands
- **Customer**: `cd c:\food-delivery-platform-main\mobile\customer && flutter clean && flutter build apk`
- **Restaurant**: `cd c:\food-delivery-platform-main\mobile\restaurant && flutter clean && flutter build apk`  
- **Rider**: `cd c:\food-delivery-platform-main\mobile\rider && flutter clean && flutter build apk`