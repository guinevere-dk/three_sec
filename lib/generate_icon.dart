import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Run this file to generate the app icon
/// flutter run -t lib/generate_icon.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Generate 1024x1024 icon
  final image = await generateIconImage(1024);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  final bytes = byteData!.buffer.asUint8List();
  
  // Save to assets/icon/app_icon.png
  final file = File('assets/icon/app_icon.png');
  await file.create(recursive: true);
  await file.writeAsBytes(bytes);
  
  print('Icon generated successfully at: ${file.path}');
  exit(0);
}

Future<ui.Image> generateIconImage(int size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint();
  
  final center = Offset(size / 2, size / 2);
  final radius = size / 2;
  
  // Background gradient (purple to pink)
  paint.shader = ui.Gradient.radial(
    center,
    radius,
    [
      const Color(0xFF6B46C1), // Deep purple
      const Color(0xFFEC4899), // Pink
    ],
    [0.0, 1.0],
  );
  canvas.drawCircle(center, radius, paint);
  
  // Draw camera/video icon
  paint.shader = null;
  paint.color = Colors.white;
  paint.style = PaintingStyle.fill;
  
  // Camera body (rounded rectangle)
  final cameraWidth = size * 0.5;
  final cameraHeight = size * 0.35;
  final cameraLeft = (size - cameraWidth) / 2;
  final cameraTop = size * 0.25;
  final cameraRect = RRect.fromRectAndRadius(
    Rect.fromLTWH(cameraLeft, cameraTop, cameraWidth, cameraHeight),
    Radius.circular(size * 0.08),
  );
  canvas.drawRRect(cameraRect, paint);
  
  // Lens circle
  final lensRadius = size * 0.12;
  final lensCenter = Offset(size * 0.4, cameraTop + cameraHeight / 2);
  canvas.drawCircle(lensCenter, lensRadius, paint);
  
  // Inner lens (darker)
  paint.color = const Color(0xFF6B46C1);
  canvas.drawCircle(lensCenter, lensRadius * 0.6, paint);
  
  // Recording indicator (red dot)
  paint.color = const Color(0xFFFF3B3B);
  final dotRadius = size * 0.06;
  final dotCenter = Offset(size * 0.75, cameraTop + size * 0.08);
  canvas.drawCircle(dotCenter, dotRadius, paint);
  
  // "3s" text
  final textPainter = TextPainter(
    text: TextSpan(
      text: '3s',
      style: TextStyle(
        color: Colors.white,
        fontSize: size * 0.25,
        fontWeight: FontWeight.bold,
        fontFamily: 'Roboto',
      ),
    ),
    textDirection: TextDirection.ltr,
  );
  textPainter.layout();
  
  final textOffset = Offset(
    (size - textPainter.width) / 2,
    cameraTop + cameraHeight + size * 0.08,
  );
  textPainter.paint(canvas, textOffset);
  
  final picture = recorder.endRecording();
  return await picture.toImage(size, size);
}
