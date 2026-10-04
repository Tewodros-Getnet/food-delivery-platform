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

    // Resize to square 512x512 to ensure perfect circle
    final size = 512;
    final resized = img.copyResize(src, width: size, height: size, interpolation: img.Interpolation.linear);

    // Create output image with transparency
    final out = img.Image(width: size, height: size, numChannels: 4);
    img.fill(out, color: img.ColorRgba8(0, 0, 0, 0)); // fully transparent

    final cx = size / 2.0;
    final cy = size / 2.0;
    final r = size / 2.0;

    // Copy pixels inside the circle, leave outside transparent
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final dx = x - cx;
        final dy = y - cy;
        if (dx * dx + dy * dy <= r * r) {
          final srcPixel = resized.getPixel(x, y);
          out.setPixel(x, y, srcPixel);
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