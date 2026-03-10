// Generates a simple app icon for YueLink.
// Run: dart scripts/generate_icon.dart
// Then: dart run flutter_launcher_icons

import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;

void main() {
  const size = 1024;
  final image = img.Image(width: size, height: size);

  // Background: indigo gradient
  final bgTop = img.ColorRgba8(99, 102, 241, 255); // #6366F1
  final bgBottom = img.ColorRgba8(79, 70, 229, 255); // #4F46E5

  for (int y = 0; y < size; y++) {
    final t = y / size;
    final r = _lerp(bgTop.r.toInt(), bgBottom.r.toInt(), t);
    final g = _lerp(bgTop.g.toInt(), bgBottom.g.toInt(), t);
    final b = _lerp(bgTop.b.toInt(), bgBottom.b.toInt(), t);
    for (int x = 0; x < size; x++) {
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }

  // Draw a rounded rectangle background with slight inset
  // (icons on most platforms get masked to rounded rect/circle)

  // Draw a stylized "link" symbol - two interlocking chain links
  final cx = size ~/ 2;
  final cy = size ~/ 2;
  final white = img.ColorRgba8(255, 255, 255, 255);
  final whiteAlpha = img.ColorRgba8(255, 255, 255, 80);

  // Draw two overlapping circles to form a link symbol
  _drawRing(image, cx - 120, cy, 200, 50, white);
  _drawRing(image, cx + 120, cy, 200, 50, white);

  // Draw a subtle "Y" letter hint in the background
  _drawThickLine(image, cx, cy - 180, cx - 100, cy - 320, 20, whiteAlpha);
  _drawThickLine(image, cx, cy - 180, cx + 100, cy - 320, 20, whiteAlpha);
  _drawThickLine(image, cx, cy - 180, cx, cy - 50, 20, whiteAlpha);

  // Save
  final dir = Directory('assets');
  if (!dir.existsSync()) dir.createSync();

  final output = File('assets/icon.png');
  output.writeAsBytesSync(img.encodePng(image));
  print('Icon generated: ${output.path} (${size}x$size)');
  print('Now run: dart run flutter_launcher_icons');
}

int _lerp(int a, int b, double t) => (a + (b - a) * t).round();

void _drawRing(
    img.Image image, int cx, int cy, int radius, int thickness, img.Color color) {
  final rOuter = radius;
  final rInner = radius - thickness;
  for (int y = cy - rOuter; y <= cy + rOuter; y++) {
    for (int x = cx - rOuter; x <= cx + rOuter; x++) {
      if (x < 0 || x >= image.width || y < 0 || y >= image.height) continue;
      final dist = sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
      if (dist <= rOuter && dist >= rInner) {
        // Anti-alias edges
        double alpha = 1.0;
        if (dist > rOuter - 2) alpha = (rOuter - dist) / 2;
        if (dist < rInner + 2) alpha = (dist - rInner) / 2;
        alpha = alpha.clamp(0.0, 1.0);
        if (alpha > 0.1) {
          final a = (alpha * 255).round();
          image.setPixelRgba(x, y, 255, 255, 255, a);
        }
      }
    }
  }
}

void _drawThickLine(
    img.Image image, int x1, int y1, int x2, int y2, int thickness, img.Color color) {
  final steps = max((x2 - x1).abs(), (y2 - y1).abs());
  if (steps == 0) return;
  for (int i = 0; i <= steps; i++) {
    final t = i / steps;
    final cx = x1 + ((x2 - x1) * t).round();
    final cy = y1 + ((y2 - y1) * t).round();
    for (int dy = -thickness ~/ 2; dy <= thickness ~/ 2; dy++) {
      for (int dx = -thickness ~/ 2; dx <= thickness ~/ 2; dx++) {
        final px = cx + dx;
        final py = cy + dy;
        if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
          if (dx * dx + dy * dy <= (thickness ~/ 2) * (thickness ~/ 2)) {
            image.setPixelRgba(px, py, 255, 255, 255, 80);
          }
        }
      }
    }
  }
}
