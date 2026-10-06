import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

void main() async {
  final apps = [
    'c:/food-delivery-platform-main/mobile/customer',
    'c:/food-delivery-platform-main/mobile/restaurant',
    'c:/food-delivery-platform-main/mobile/rider',
  ];

  for (final appDir in apps) {
    final inputPath = '$appDir/assets/images/logo.png';
    final outputPath = '$appDir/assets/images/logo_circle.png';

    final inputFile = File(inputPath);
    if (!inputFile.existsSync()) {
      print('SKIP: $inputPath not found');
      continue;
    }

    final bytes = inputFile.readAsBytesSync();
    final src = img.decodePng(bytes);
    if (src == null) {
      print('ERROR: Could not decode $inputPath');
      continue;
    }

    // Create 1024x1024 canvas for Android 12+ adaptive icon compatibility
    final size = 1024;
    final out = img.Image(width: size, height: size, numChannels: 4);
    img.fill(out, color: img.ColorRgba8(0, 0, 0, 0)); // fully transparent

    // Android 12+ safe zone: use 60% of canvas for actual logo (20% padding on all sides)
    final logoSize = (size * 0.6).round(); // 614 pixels for the actual logo
    final logoOffset = (size * 0.2).round(); // 205 pixel offset from edges

    // Resize source image to fit the safe zone
    final resized = img.copyResize(src, width: logoSize, height: logoSize, interpolation: img.Interpolation.linear);

    // Circle parameters for the logo area
    final cx = size / 2.0;
    final cy = size / 2.0;
    final r = logoSize / 2.0; // Circle radius matches logo size

    // Copy pixels inside the circle, with proper offset for centering
    for (int y = 0; y < logoSize; y++) {
      for (int x = 0; x < logoSize; x++) {
        final dx = x - logoSize / 2.0;
        final dy = y - logoSize / 2.0;
        if (dx * dx + dy * dy <= r * r) {
          final srcPixel = resized.getPixel(x, y);
          final outX = x + logoOffset;
          final outY = y + logoOffset;
          out.setPixel(outX, outY, srcPixel);
        }
        // else: remains transparent
      }
    }

    final outBytes = img.encodePng(out);
    File(outputPath).writeAsBytesSync(outBytes);
    print('Created: $outputPath');
  }

  print('Done.');
}