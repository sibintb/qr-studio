import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr/qr.dart' as qr_algo;
import 'package:share_plus/share_plus.dart';
import 'package:universal_html/html.dart' as html; // Safe import for Web/Mobile
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const QrMakerApp());
}

// --- Data Models & Enums ---

enum QrDataType {
  url,
  text,
  wifi,
  email,
  phone,
  sms,
  whatsapp,
  location,
  vcard,
  event
}

enum QrStyle { square, circle, rounded, classy }

class QrTheme {
  final String name;
  final Color fg;
  final Color bg;
  final QrStyle style;

  const QrTheme(this.name, this.fg, this.bg, this.style);
}

// --- Custom Painter ---

class QrPainter extends CustomPainter {
  final qr_algo.QrCode qrCode;
  final QrStyle style;
  final Color fgColor;
  final Color bgColor;
  final ui.Image? embeddedImage;
  final double imageSizeRatio;

  QrPainter({
    required this.qrCode,
    required this.style,
    required this.fgColor,
    required this.bgColor,
    this.embeddedImage,
    this.imageSizeRatio = 0.2,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final bgPaint = Paint()..color = bgColor;
    final fgPaint = Paint()..color = fgColor;

    // 1. Draw Background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final qrImage = qr_algo.QrImage(qrCode);
    final double pixelSize = size.width / qrImage.moduleCount;

    // Helper to check if a module is part of the 3 Finder Patterns
    bool isFinder(int x, int y) {
      final int count = qrImage.moduleCount;
      // Top-Left (7x7)
      if (x < 7 && y < 7) return true;
      // Top-Right (7x7)
      if (x >= count - 7 && y < 7) return true;
      // Bottom-Left (7x7)
      if (x < 7 && y >= count - 7) return true;
      return false;
    }

    // Helper to check connectivity
    bool hasNeighbor(int x, int y, int dx, int dy) {
      int nx = x + dx;
      int ny = y + dy;
      if (nx < 0 ||
          nx >= qrImage.moduleCount ||
          ny < 0 ||
          ny >= qrImage.moduleCount) return false;
      if (isFinder(nx, ny)) return false; // Don't merge with finder patterns
      return qrImage.isDark(ny, nx);
    }

    // 2. Draw Data Modules (Excluding Finders)
    for (var x = 0; x < qrImage.moduleCount; x++) {
      for (var y = 0; y < qrImage.moduleCount; y++) {
        if (isFinder(x, y)) continue; // Skip finder areas

        if (qrImage.isDark(y, x)) {
          // Logo Occlusion
          if (embeddedImage != null) {
            final center = qrImage.moduleCount / 2;
            final logoSizeModules = qrImage.moduleCount * imageSizeRatio;
            final start = center - (logoSizeModules / 2);
            final end = center + (logoSizeModules / 2);
            if (x >= start && x < end && y >= start && y < end) continue;
          }

          final rect =
              Rect.fromLTWH(x * pixelSize, y * pixelSize, pixelSize, pixelSize);

          if (style == QrStyle.rounded || style == QrStyle.classy) {
            // Liquid/Connected Logic
            bool up = hasNeighbor(x, y, 0, -1);
            bool down = hasNeighbor(x, y, 0, 1);
            bool left = hasNeighbor(x, y, -1, 0);
            bool right = hasNeighbor(x, y, 1, 0);

            // Calculate radii
            // Max radius is half the pixel size
            double r = pixelSize / 2;

            // Rounded: All corners candidates. Classy: Only TL and BR candidates.
            Radius tl = (style == QrStyle.rounded || style == QrStyle.classy) &&
                    !up &&
                    !left
                ? Radius.circular(r)
                : Radius.zero;
            Radius tr = (style == QrStyle.rounded) && !up && !right
                ? Radius.circular(r)
                : Radius.zero;
            Radius br = (style == QrStyle.rounded || style == QrStyle.classy) &&
                    !down &&
                    !right
                ? Radius.circular(r)
                : Radius.zero;
            Radius bl = (style == QrStyle.rounded) && !down && !left
                ? Radius.circular(r)
                : Radius.zero;

            canvas.drawRRect(
                RRect.fromRectAndCorners(rect,
                    topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl),
                fgPaint);
          } else {
            // Standard Shapes
            _drawModuleShape(canvas, rect, style, fgPaint);
          }
        }
      }
    }

    // 3. Draw Custom Finder Patterns
    // Top-Left
    _drawFinderPattern(canvas, 0, 0, pixelSize, style, fgPaint);
    // Top-Right
    _drawFinderPattern(canvas, (qrImage.moduleCount - 7) * pixelSize, 0,
        pixelSize, style, fgPaint);
    // Bottom-Left
    _drawFinderPattern(canvas, 0, (qrImage.moduleCount - 7) * pixelSize,
        pixelSize, style, fgPaint);

    // 4. Draw Image
    if (embeddedImage != null) {
      final logoSize = size.width * imageSizeRatio;
      final logoOffset = (size.width - logoSize) / 2;
      final srcRect = Rect.fromLTWH(0, 0, embeddedImage!.width.toDouble(),
          embeddedImage!.height.toDouble());
      final dstRect = Rect.fromLTWH(logoOffset, logoOffset, logoSize, logoSize);
      canvas.drawImageRect(embeddedImage!, srcRect, dstRect, Paint());
    }
  }

  void _drawModuleShape(Canvas canvas, Rect rect, QrStyle style, Paint paint) {
    switch (style) {
      case QrStyle.square:
        canvas.drawRect(rect, paint);
        break;
      case QrStyle.circle:
        final center =
            Offset(rect.left + rect.width / 2, rect.top + rect.height / 2);
        canvas.drawCircle(center, rect.width / 2, paint);
        break;
      default:
        canvas.drawRect(rect, paint);
    }
  }

  void _drawFinderPattern(Canvas canvas, double x, double y, double cellSize,
      QrStyle style, Paint paint) {
    final double outerSize = 7 * cellSize;
    final Rect outerRect = Rect.fromLTWH(x, y, outerSize, outerSize);
    final Rect innerCutout =
        Rect.fromLTWH(x + cellSize, y + cellSize, 5 * cellSize, 5 * cellSize);
    final Rect centerRect = Rect.fromLTWH(
        x + 2 * cellSize, y + 2 * cellSize, 3 * cellSize, 3 * cellSize);

    if (style == QrStyle.square) {
      final Path ring = Path()
        ..addRect(outerRect)
        ..addRect(innerCutout)
        ..fillType = PathFillType.evenOdd;
      canvas.drawPath(ring, paint);
      canvas.drawRect(centerRect, paint);
    } else if (style == QrStyle.circle) {
      final center = Offset(x + outerSize / 2, y + outerSize / 2);
      final double outerRadius = outerSize / 2;
      final double innerRadius = (outerSize - 2 * cellSize) / 2;
      final Path ring = Path()
        ..addOval(Rect.fromCircle(center: center, radius: outerRadius))
        ..addOval(Rect.fromCircle(center: center, radius: innerRadius))
        ..fillType = PathFillType.evenOdd;
      canvas.drawPath(ring, paint);
      canvas.drawCircle(center, (3 * cellSize) / 2, paint);
    } else if (style == QrStyle.rounded || style == QrStyle.classy) {
      // Rounded style for finders (used by both Rounded and Classy per request)
      final double r = cellSize * 2.5;
      final double rIn = r - cellSize;
      final double rDot = cellSize * 1.0;

      final Path ring = Path()
        ..addRRect(RRect.fromRectAndRadius(outerRect, Radius.circular(r)))
        ..addRRect(RRect.fromRectAndRadius(innerCutout, Radius.circular(rIn)))
        ..fillType = PathFillType.evenOdd;
      canvas.drawPath(ring, paint);

      canvas.drawRRect(
          RRect.fromRectAndRadius(centerRect, Radius.circular(rDot)), paint);
    }
  }

  @override
  bool shouldRepaint(covariant QrPainter oldDelegate) {
    return oldDelegate.qrCode != qrCode ||
        oldDelegate.style != style ||
        oldDelegate.fgColor != fgColor ||
        oldDelegate.bgColor != bgColor ||
        oldDelegate.embeddedImage != embeddedImage;
  }
}

// --- Main App Widget ---

class QrMakerApp extends StatelessWidget {
  const QrMakerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pro QR Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2196F3),
          brightness: Brightness.light,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2196F3),
          brightness: Brightness.dark,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const QrHomePage(),
    );
  }
}

class QrHomePage extends StatefulWidget {
  const QrHomePage({super.key});

  @override
  State<QrHomePage> createState() => _QrHomePageState();
}

class _QrHomePageState extends State<QrHomePage> {
  final GlobalKey _qrKey = GlobalKey();

  // --- State Variables ---
  QrDataType _selectedType = QrDataType.url;

  // Data Fields
  final Map<String, TextEditingController> _controllers = {};
  final TextEditingController _fileNameController =
      TextEditingController(text: "my_qr_code");

  // Event Specific State
  DateTime _eventStartDate = DateTime.now();
  TimeOfDay _eventStartTime = TimeOfDay.now();
  DateTime _eventEndDate = DateTime.now().add(const Duration(hours: 1));
  TimeOfDay _eventEndTime =
      TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1)));

  // Appearance
  Color _fgColor = Colors.black;
  Color _bgColor = Colors.white;
  QrStyle _qrStyle = QrStyle.square;
  int _errorCorrectLevel = qr_algo.QrErrorCorrectLevel.Q;

  // Logo
  File? _logoFile;
  String _logoUrl = "";
  bool _useLogoUrl = false;
  double _logoSize = 0.2;
  ui.Image? _decodedLogoImage;

  // --- Presets ---
  final List<QrTheme> _presets = [
    const QrTheme("Classic Black", Colors.black, Colors.white, QrStyle.square),
    const QrTheme(
        "Classic Blue", Color(0xFF1565C0), Colors.white, QrStyle.square),
    const QrTheme(
        "Social Circle", Color(0xFFE91E63), Colors.white, QrStyle.circle),
    const QrTheme(
        "Tech Rounded", Color(0xFF009688), Colors.white, QrStyle.rounded),
    const QrTheme(
        "Classy Teal", Color(0xFF00695C), Color(0xFFE0F2F1), QrStyle.classy),
    const QrTheme(
        "Dark Mode", Color(0xFF64FFDA), Color(0xFF212121), QrStyle.square),
    const QrTheme(
        "Forest", Color(0xFF2E7D32), Color(0xFFE8F5E9), QrStyle.rounded),
    const QrTheme(
        "Sunset", Color(0xFFD84315), Color(0xFFFFF3E0), QrStyle.circle),
    const QrTheme(
        "Ocean", Color(0xFF0277BD), Color(0xFFE1F5FE), QrStyle.rounded),
    const QrTheme(
        "Luxury", Color(0xFFFFD700), Color(0xFF000000), QrStyle.classy),
    const QrTheme(
        "Berry", Color(0xFF880E4F), Color(0xFFFCE4EC), QrStyle.circle),
    const QrTheme(
        "Slate", Color(0xFF37474F), Color(0xFFECEFF1), QrStyle.square),
    const QrTheme(
        "Mint", Color(0xFF00BFA5), Color(0xFFE0F2F1), QrStyle.rounded),
    const QrTheme(
        "Lavender", Color(0xFF673AB7), Color(0xFFEDE7F6), QrStyle.circle),
    const QrTheme("Crimson", Color(0xFFB71C1C), Colors.white, QrStyle.classy),
    const QrTheme("Midnight", Colors.white, Color(0xFF1A237E), QrStyle.square),
    const QrTheme("Neon", Color(0xFF00E676), Colors.black, QrStyle.rounded),
    const QrTheme(
        "Coral", Color(0xFFFFAB91), Color(0xFF3E2723), QrStyle.circle),
    const QrTheme(
        "Indigo", Color(0xFFC5CAE9), Color(0xFF1A237E), QrStyle.classy),
    const QrTheme(
        "Minimal", Color(0xFF616161), Color(0xFFFAFAFA), QrStyle.square),
  ];

  QrTheme? _selectedTheme;

  @override
  void initState() {
    super.initState();
    _selectedTheme = _presets.first;
    _initializeControllers();
  }

  void _initializeControllers() {
    for (var key in [
      'text',
      'url',
      'ssid',
      'password',
      'phone',
      'email',
      'subject',
      'body',
      'lat',
      'long',
      'name',
      'org',
      'title',
      'event_title',
      'event_loc'
    ]) {
      _controllers[key] = TextEditingController();
    }
    _controllers['url']?.text = "https://sibintb.github.io";
    _controllers['encryption'] = TextEditingController(text: "WPA/WPA2");
    _controllers['hidden'] = TextEditingController(text: "false");
  }

  @override
  void dispose() {
    for (var c in _controllers.values) {
      c.dispose();
    }
    _fileNameController.dispose();
    super.dispose();
  }

  // --- Data Generation Logic ---

  String _generateQrData() {
    switch (_selectedType) {
      case QrDataType.text:
        return _controllers['text']?.text ?? "";
      case QrDataType.url:
        String url = _controllers['url']?.text ?? "";
        if (url.isNotEmpty && !url.startsWith('http')) url = 'https://$url';
        return url;
      case QrDataType.wifi:
        final ssid = _esc(_controllers['ssid']?.text);
        final pass = _esc(_controllers['password']?.text);
        final enc = _controllers['encryption']?.text ?? "WPA";
        final hidden =
            _controllers['hidden']?.text == "true" ? "true" : "false";
        return "WIFI:S:$ssid;T:$enc;P:$pass;H:$hidden;;";
      case QrDataType.email:
        final email = _controllers['email']?.text ?? "";
        final sub = _controllers['subject']?.text ?? "";
        final body = _controllers['body']?.text ?? "";
        return "mailto:$email?subject=${Uri.encodeComponent(sub)}&body=${Uri.encodeComponent(body)}";
      case QrDataType.phone:
        return "tel:${_controllers['phone']?.text ?? ""}";
      case QrDataType.sms:
        return "smsto:${_controllers['phone']?.text}:${_controllers['body']?.text}";
      case QrDataType.whatsapp:
        String phone = _controllers['phone']?.text ?? "";
        phone = phone.replaceAll(RegExp(r'[^0-9]'), '');
        final text = _controllers['body']?.text ?? "";
        return "https://wa.me/$phone?text=${Uri.encodeComponent(text)}";
      case QrDataType.location:
        return "geo:${_controllers['lat']?.text},${_controllers['long']?.text}";
      case QrDataType.vcard:
        return """BEGIN:VCARD
VERSION:3.0
N:${_controllers['name']?.text}
ORG:${_controllers['org']?.text}
TITLE:${_controllers['title']?.text}
TEL:${_controllers['phone']?.text}
EMAIL:${_controllers['email']?.text}
END:VCARD""";
      case QrDataType.event:
        final start = DateTime(_eventStartDate.year, _eventStartDate.month,
            _eventStartDate.day, _eventStartTime.hour, _eventStartTime.minute);
        final end = DateTime(_eventEndDate.year, _eventEndDate.month,
            _eventEndDate.day, _eventEndTime.hour, _eventEndTime.minute);
        return """BEGIN:VEVENT
SUMMARY:${_controllers['event_title']?.text}
LOCATION:${_controllers['event_loc']?.text}
DTSTART:${DateFormat('yyyyMMddTHHmmss').format(start)}
DTEND:${DateFormat('yyyyMMddTHHmmss').format(end)}
END:VEVENT""";
    }
  }

  String _esc(String? val) =>
      (val == null) ? "" : val.replaceAll(':', '\\:').replaceAll(';', '\\;');

  // --- Export Logic ---

  Future<void> _exportImage(String format) async {
    final data = _generateQrData();
    if (data.isEmpty) return;

    try {
      RenderRepaintBoundary? boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

      if (boundary == null) {
        _showError("Preview not loaded. Please open preview first.");
        return;
      }

      ui.Image image = await boundary.toImage(pixelRatio: 4.0);
      ui.ImageByteFormat byteFormat =
          format == 'png' ? ui.ImageByteFormat.png : ui.ImageByteFormat.png;

      ByteData? byteData = await image.toByteData(format: byteFormat);

      if (byteData != null) {
        final Uint8List bytes = byteData.buffer.asUint8List();

        String userFileName = _fileNameController.text.trim();
        if (userFileName.isEmpty) {
          userFileName = "qr_export_${DateTime.now().millisecondsSinceEpoch}";
        }
        final String fileName = '$userFileName.$format';

        final String mimeType = format == 'png' ? 'image/png' : 'image/jpeg';

        if (kIsWeb) {
          final blob = html.Blob([bytes], mimeType);
          final url = html.Url.createObjectUrlFromBlob(blob);
          final anchor = html.AnchorElement(href: url)
            ..setAttribute("download", fileName)
            ..click();
          html.Url.revokeObjectUrl(url);
        } else {
          final directory = await getTemporaryDirectory();
          final path = '${directory.path}/$fileName';
          final file = File(path);
          await file.writeAsBytes(bytes);
          await Share.shareXFiles([XFile(path)],
              text: 'Shared via Pro QR Studio');
        }
      }
    } catch (e) {
      _showError('Export failed: $e');
    }
  }

  Future<void> _exportSvg() async {
    final data = _generateQrData();
    if (data.isEmpty) return;

    try {
      final qrValidation = qr_algo.QrCode.fromData(
        data: data,
        errorCorrectLevel: _errorCorrectLevel,
      );
      final qrImage = qr_algo.QrImage(qrValidation);
      final StringBuffer svg = StringBuffer();
      final double pixelSize = 10;
      final double border = 4;
      final double totalSize = (qrImage.moduleCount + (border * 2)) * pixelSize;

      svg.writeln('<?xml version="1.0" encoding="UTF-8"?>');
      svg.writeln(
          '<svg width="$totalSize" height="$totalSize" viewBox="0 0 $totalSize $totalSize" version="1.1" xmlns="http://www.w3.org/2000/svg">');

      String hexBg = '#${_bgColor.value.toRadixString(16).substring(2)}';
      svg.writeln(
          '<rect x="0" y="0" width="$totalSize" height="$totalSize" fill="$hexBg" />');

      String hexFg = '#${_fgColor.value.toRadixString(16).substring(2)}';

      // Helper to determine if module is finder
      bool isFinder(int x, int y) {
        final int count = qrImage.moduleCount;
        if (x < 7 && y < 7) return true;
        if (x >= count - 7 && y < 7) return true;
        if (x < 7 && y >= count - 7) return true;
        return false;
      }

      bool hasNeighbor(int x, int y, int dx, int dy) {
        int nx = x + dx;
        int ny = y + dy;
        if (nx < 0 ||
            nx >= qrImage.moduleCount ||
            ny < 0 ||
            ny >= qrImage.moduleCount) return false;
        if (isFinder(nx, ny)) return false;
        return qrImage.isDark(ny, nx);
      }

      // 1. Draw Data Modules (Skip Finders)
      for (var x = 0; x < qrImage.moduleCount; x++) {
        for (var y = 0; y < qrImage.moduleCount; y++) {
          if (isFinder(x, y)) continue;

          if (qrImage.isDark(y, x)) {
            if (_useLogoUrl || _logoFile != null) {
              final center = qrImage.moduleCount / 2;
              final limit = (qrImage.moduleCount * _logoSize) / 2;
              if (x > center - limit &&
                  x < center + limit &&
                  y > center - limit &&
                  y < center + limit) continue;
            }
            final double posX = (x + border) * pixelSize;
            final double posY = (y + border) * pixelSize;

            // Draw Data Shapes
            if (_qrStyle == QrStyle.circle) {
              final r = pixelSize / 2;
              final cx = posX + r;
              final cy = posY + r;
              svg.writeln('<circle cx="$cx" cy="$cy" r="$r" fill="$hexFg" />');
            } else if (_qrStyle == QrStyle.rounded ||
                _qrStyle == QrStyle.classy) {
              // Liquid Logic for SVG
              bool up = hasNeighbor(x, y, 0, -1);
              bool down = hasNeighbor(x, y, 0, 1);
              bool left = hasNeighbor(x, y, -1, 0);
              bool right = hasNeighbor(x, y, 1, 0);

              final r = pixelSize / 2;
              final w = pixelSize;

              // Build path for rounded rect with conditional corners
              List<String> pathCmds = [];

              // Start Top-Left
              if ((_qrStyle == QrStyle.rounded || _qrStyle == QrStyle.classy) &&
                  !up &&
                  !left) {
                pathCmds
                    .add('M $posX,${posY + r} Q $posX,$posY ${posX + r},$posY');
              } else {
                pathCmds.add('M $posX,$posY');
              }

              // Top-Right
              if ((_qrStyle == QrStyle.rounded) && !up && !right) {
                pathCmds.add(
                    'L ${posX + w - r},$posY Q ${posX + w},$posY ${posX + w},${posY + r}');
              } else {
                pathCmds.add('L ${posX + w},$posY');
              }

              // Bottom-Right
              if ((_qrStyle == QrStyle.rounded || _qrStyle == QrStyle.classy) &&
                  !down &&
                  !right) {
                pathCmds.add(
                    'L ${posX + w},${posY + w - r} Q ${posX + w},${posY + w} ${posX + w - r},${posY + w}');
              } else {
                pathCmds.add('L ${posX + w},${posY + w}');
              }

              // Bottom-Left
              if ((_qrStyle == QrStyle.rounded) && !down && !left) {
                pathCmds.add(
                    'L ${posX + r},${posY + w} Q $posX,${posY + w} $posX,${posY + w - r}');
              } else {
                pathCmds.add('L $posX,${posY + w}');
              }

              pathCmds.add('Z');
              svg.writeln('<path d="${pathCmds.join(' ')}" fill="$hexFg" />');
            } else {
              svg.writeln(
                  '<rect x="$posX" y="$posY" width="$pixelSize" height="$pixelSize" fill="$hexFg" />');
            }
          }
        }
      }

      // 2. Draw Finder Patterns (Custom Paths)
      void drawFinder(double bx, double by) {
        final outerSize = 7 * pixelSize;
        // Outer Frame
        if (_qrStyle == QrStyle.square) {
          String path = 'M $bx,$by h $outerSize v $outerSize h -$outerSize z '
              'M ${bx + pixelSize},${by + pixelSize} v ${5 * pixelSize} h ${5 * pixelSize} v -${5 * pixelSize} z';
          svg.writeln('<path d="$path" fill="$hexFg" fill-rule="evenodd" />');
          svg.writeln(
              '<rect x="${bx + 2 * pixelSize}" y="${by + 2 * pixelSize}" width="${3 * pixelSize}" height="${3 * pixelSize}" fill="$hexFg" />');
        } else if (_qrStyle == QrStyle.circle) {
          final cx = bx + outerSize / 2;
          final cy = by + outerSize / 2;
          final rOut = outerSize / 2;
          final rIn = rOut - pixelSize;
          String path =
              'M $cx,${cy - rOut} A $rOut,$rOut 0 1,1 $cx,${cy + rOut} A $rOut,$rOut 0 1,1 $cx,${cy - rOut} Z '
              'M $cx,${cy - rIn}  A $rIn,$rIn   0 1,0 $cx,${cy + rIn}  A $rIn,$rIn   0 1,0 $cx,${cy - rIn} Z';
          svg.writeln('<path d="$path" fill="$hexFg" fill-rule="evenodd" />');
          final rDot = 1.5 * pixelSize;
          svg.writeln('<circle cx="$cx" cy="$cy" r="$rDot" fill="$hexFg" />');
        } else if (_qrStyle == QrStyle.rounded || _qrStyle == QrStyle.classy) {
          final r = 2.5 * pixelSize;
          final rIn = r - pixelSize;
          // Using simple Rect with Rx Ry works well for rounded finders in SVG if we don't need complex boolean ops,
          // but creating a hole requires path.
          // We can use a path made of 2 rects, one clockwise, one counter-clockwise for hole? Or Fill rule evenodd.

          // Outer
          String makeRR(double px, double py, double size, double rad) {
            // M x+r, y L x+w-r, y Q x+w, y x+w, y+r ...
            return 'M ${px + rad},$py L ${px + size - rad},$py Q ${px + size},$py ${px + size},${py + rad} L ${px + size},${py + size - rad} Q ${px + size},${py + size} ${px + size - rad},${py + size} L ${px + rad},${py + size} Q $px,${py + size} $px,${py + size - rad} L $px,${py + rad} Q $px,$py ${px + rad},$py Z';
          }

          String outer = makeRR(bx, by, outerSize, r);
          String inner =
              makeRR(bx + pixelSize, by + pixelSize, 5 * pixelSize, rIn);
          svg.writeln(
              '<path d="$outer $inner" fill="$hexFg" fill-rule="evenodd" />');

          // Dot
          String dot = makeRR(
              bx + 2 * pixelSize, by + 2 * pixelSize, 3 * pixelSize, pixelSize);
          svg.writeln('<path d="$dot" fill="$hexFg" />');
        }
      }

      drawFinder(border * pixelSize, border * pixelSize); // TL
      drawFinder((qrImage.moduleCount - 7 + border) * pixelSize,
          border * pixelSize); // TR
      drawFinder(border * pixelSize,
          (qrImage.moduleCount - 7 + border) * pixelSize); // BL

      svg.writeln('</svg>');

      String userFileName = _fileNameController.text.trim();
      if (userFileName.isEmpty)
        userFileName = "qr_vector_${DateTime.now().millisecondsSinceEpoch}";
      final String fileName = '$userFileName.svg';

      if (kIsWeb) {
        final blob = html.Blob([svg.toString()], 'image/svg+xml');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute("download", fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        final directory = await getTemporaryDirectory();
        final path = '${directory.path}/$fileName';
        final file = File(path);
        await file.writeAsString(svg.toString());
        await Share.shareXFiles([XFile(path)], text: 'QR Vector File');
      }
    } catch (e) {
      _showError('SVG Export failed: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --- UI Helpers ---

  Future<void> _pickLogo() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _logoFile = File(image.path);
        _useLogoUrl = false;
        _loadLogoImage();
      });
    }
  }

  void _loadLogoImage() async {
    if (_logoFile != null) {
      final bytes = await _logoFile!.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      setState(() {
        _decodedLogoImage = frame.image;
      });
    }
  }

  void _applyTheme(QrTheme theme) {
    setState(() {
      _selectedTheme = theme;
      _fgColor = theme.fg;
      _bgColor = theme.bg;
      _qrStyle = theme.style;
    });
  }

  Future<void> _launchMail() async {
    final Uri emailLaunchUri = Uri(
        scheme: 'mailto',
        path: 'sibintb@gmail.com',
        query: 'subject=QR App Inquiry');
    try {
      await launchUrl(emailLaunchUri);
    } catch (e) {
      _showError("Could not launch email client.");
    }
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _eventStartDate : _eventEndDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      setState(() {
        if (isStart)
          _eventStartDate = picked;
        else
          _eventEndDate = picked;
      });
    }
  }

  Future<void> _selectTime(BuildContext context, bool isStart) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _eventStartTime : _eventEndTime,
    );
    if (picked != null) {
      setState(() {
        if (isStart)
          _eventStartTime = picked;
        else
          _eventEndTime = picked;
      });
    }
  }

  // --- Modals ---

  void _showPreviewModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 16),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text("Preview & Export",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Center(child: _buildPreviewContent(true)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Widget Builders ---

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      appBar: AppBar(title: const Text("QR Studio")),
      body: Column(
        children: [
          Expanded(
            child: isWide ? _buildWideLayout() : _buildMobileLayout(),
          ),
          _buildFooter(),
        ],
      ),
      floatingActionButton: !isWide
          ? FloatingActionButton.extended(
              onPressed: () => _showPreviewModal(context),
              icon: const Icon(Icons.qr_code_2),
              label: const Text("Preview"),
            )
          : null,
    );
  }

  Widget _buildFooter() {
    return Container(
      width: double.infinity,
      color: Colors.grey.shade200,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: InkWell(
        onTap: _launchMail,
        child: RichText(
          textAlign: TextAlign.center,
          text: const TextSpan(
            style: TextStyle(color: Colors.black54, fontSize: 12),
            children: [
              TextSpan(text: "Designed and Developed by "),
              TextSpan(
                text: "CBn",
                style:
                    TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return _buildControlsSection();
  }

  Widget _buildWideLayout() {
    return Row(
      children: [
        Expanded(flex: 7, child: _buildControlsSection()),
        const VerticalDivider(width: 1),
        Expanded(
            flex: 3,
            child: Center(
                child:
                    SingleChildScrollView(child: _buildPreviewContent(false)))),
      ],
    );
  }

  Widget _buildPreviewContent(bool isMobile) {
    final qrValidation = qr_algo.QrCode.fromData(
      data: _generateQrData(),
      errorCorrectLevel: _errorCorrectLevel,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RepaintBoundary(
          key: _qrKey,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _bgColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 15,
                    offset: const Offset(0, 5))
              ],
            ),
            child: CustomPaint(
              size: Size.square(isMobile ? 250 : 280),
              painter: QrPainter(
                qrCode: qrValidation,
                style: _qrStyle,
                fgColor: _fgColor,
                bgColor: _bgColor,
                embeddedImage: _decodedLogoImage,
                imageSizeRatio: _logoSize,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 8.0),
          child: TextField(
            controller: _fileNameController,
            decoration: const InputDecoration(
              labelText: "Filename (optional)",
              border: OutlineInputBorder(),
              isDense: true,
              suffixText: ".png/.svg",
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _exportBtn("PNG", Icons.download, () => _exportImage('png')),
            _exportBtn("JPG", Icons.download, () => _exportImage('jpg')),
            _exportBtn("SVG", Icons.code, _exportSvg),
          ],
        )
      ],
    );
  }

  Widget _exportBtn(String label, IconData icon, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        textStyle: const TextStyle(fontSize: 12),
      ),
    );
  }

  Widget _buildControlsSection() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        _buildSectionHeader("Content Type"),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<QrDataType>(
              isExpanded: true,
              value: _selectedType,
              items: const [
                DropdownMenuItem(
                    value: QrDataType.url,
                    child: Row(children: [
                      Icon(Icons.link),
                      SizedBox(width: 8),
                      Text("Website URL")
                    ])),
                DropdownMenuItem(
                    value: QrDataType.text,
                    child: Row(children: [
                      Icon(Icons.text_fields),
                      SizedBox(width: 8),
                      Text("Plain Text")
                    ])),
                DropdownMenuItem(
                    value: QrDataType.whatsapp,
                    child: Row(children: [
                      Icon(Icons.chat),
                      SizedBox(width: 8),
                      Text("WhatsApp")
                    ])),
                DropdownMenuItem(
                    value: QrDataType.wifi,
                    child: Row(children: [
                      Icon(Icons.wifi),
                      SizedBox(width: 8),
                      Text("WiFi Network")
                    ])),
                DropdownMenuItem(
                    value: QrDataType.phone,
                    child: Row(children: [
                      Icon(Icons.phone),
                      SizedBox(width: 8),
                      Text("Call / Phone")
                    ])),
                DropdownMenuItem(
                    value: QrDataType.sms,
                    child: Row(children: [
                      Icon(Icons.sms),
                      SizedBox(width: 8),
                      Text("SMS Message")
                    ])),
                DropdownMenuItem(
                    value: QrDataType.email,
                    child: Row(children: [
                      Icon(Icons.email),
                      SizedBox(width: 8),
                      Text("Email")
                    ])),
                DropdownMenuItem(
                    value: QrDataType.vcard,
                    child: Row(children: [
                      Icon(Icons.contact_page),
                      SizedBox(width: 8),
                      Text("Contact (vCard)")
                    ])),
                DropdownMenuItem(
                    value: QrDataType.location,
                    child: Row(children: [
                      Icon(Icons.location_on),
                      SizedBox(width: 8),
                      Text("Location (Geo)")
                    ])),
                DropdownMenuItem(
                    value: QrDataType.event,
                    child: Row(children: [
                      Icon(Icons.event),
                      SizedBox(width: 8),
                      Text("Calendar Event")
                    ])),
              ],
              onChanged: (QrDataType? newValue) {
                if (newValue != null) {
                  setState(() => _selectedType = newValue);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildInputFields(),
          ),
        ),

        const SizedBox(height: 24),
        _buildSectionHeader("Customization"),

        // Theme Selection
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<QrTheme>(
              isExpanded: true,
              hint: const Text("Select a Theme"),
              value: _selectedTheme,
              items: _presets
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Row(
                          children: [
                            Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                    color: t.fg, shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Text(t.name),
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) _applyTheme(val);
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Colors
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text("Manual Colors"),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => _pickColor(true),
                child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                        color: _fgColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey))),
              ),
              const SizedBox(width: 8),
              const Text("FG"),
              const SizedBox(width: 20),
              GestureDetector(
                onTap: () => _pickColor(false),
                child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                        color: _bgColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey))),
              ),
              const SizedBox(width: 8),
              const Text("BG"),
            ],
          ),
        ),

        const Divider(),
        const Text("QR Style", style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),

        LayoutBuilder(
          builder: (context, constraints) {
            final isSmall = constraints.maxWidth < 400;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: isSmall ? 2 : 4,
              childAspectRatio: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                _buildStyleOption("Square", QrStyle.square),
                _buildStyleOption("Circle", QrStyle.circle),
                _buildStyleOption("Rounded", QrStyle.rounded),
                _buildStyleOption("Classy", QrStyle.classy),
              ],
            );
          },
        ),

        const SizedBox(height: 16),
        const Text("Technical Settings",
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          value: _errorCorrectLevel,
          decoration: const InputDecoration(
              labelText: "Error Correction Level",
              border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(
                value: qr_algo.QrErrorCorrectLevel.L, child: Text("Low (7%)")),
            DropdownMenuItem(
                value: qr_algo.QrErrorCorrectLevel.M,
                child: Text("Medium (15%)")),
            DropdownMenuItem(
                value: qr_algo.QrErrorCorrectLevel.Q,
                child: Text("High (25%)")),
            DropdownMenuItem(
                value: qr_algo.QrErrorCorrectLevel.H,
                child: Text("Highest (30%)")),
          ],
          onChanged: (val) {
            if (val != null) setState(() => _errorCorrectLevel = val);
          },
        ),

        const SizedBox(height: 16),

        // Logo
        ExpansionTile(
          title: const Text("Logo Overlay"),
          leading: const Icon(Icons.image),
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickLogo,
                          icon: const Icon(Icons.upload_file),
                          label: const Text("Upload Image"),
                        ),
                      ),
                      if (_logoFile != null)
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _logoFile = null;
                            _decodedLogoImage = null;
                          }),
                        )
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    decoration:
                        const InputDecoration(labelText: "Or Image URL"),
                    onChanged: (val) {
                      setState(() {
                        _logoUrl = val;
                        _useLogoUrl = val.isNotEmpty;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  if (_logoFile != null || (_useLogoUrl && _logoUrl.isNotEmpty))
                    Row(
                      children: [
                        const Text("Size: "),
                        Expanded(
                          child: Slider(
                            value: _logoSize,
                            min: 0.1,
                            max: 0.3,
                            onChanged: (v) => setState(() => _logoSize = v),
                          ),
                        )
                      ],
                    )
                ],
              ),
            )
          ],
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildStyleOption(String title, QrStyle style) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: RadioListTile<QrStyle>(
        title: Text(title, style: const TextStyle(fontSize: 13)),
        value: style,
        groupValue: _qrStyle,
        onChanged: (QrStyle? value) {
          if (value != null) setState(() => _qrStyle = value);
        },
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        dense: true,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildInputFields() {
    final commonInputDec = const InputDecoration(border: OutlineInputBorder());

    switch (_selectedType) {
      case QrDataType.text:
        return TextField(
            controller: _controllers['text'],
            decoration: commonInputDec.copyWith(labelText: "Enter Text"),
            maxLines: 4,
            onChanged: (_) => setState(() {}));
      case QrDataType.url:
        return TextField(
            controller: _controllers['url'],
            decoration:
                commonInputDec.copyWith(labelText: "Website URL (https://...)"),
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() {}));
      case QrDataType.whatsapp:
        return Column(
          children: [
            TextField(
                controller: _controllers['phone'],
                decoration: commonInputDec.copyWith(
                    labelText: "WhatsApp Number (with Country Code)"),
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {})),
            const SizedBox(height: 10),
            TextField(
                controller: _controllers['body'],
                decoration:
                    commonInputDec.copyWith(labelText: "Pre-filled Message"),
                maxLines: 3,
                onChanged: (_) => setState(() {})),
          ],
        );
      case QrDataType.wifi:
        return Column(
          children: [
            TextField(
                controller: _controllers['ssid'],
                decoration:
                    commonInputDec.copyWith(labelText: "Network Name (SSID)"),
                onChanged: (_) => setState(() {})),
            const SizedBox(height: 10),
            TextField(
                controller: _controllers['password'],
                decoration: commonInputDec.copyWith(labelText: "Password"),
                obscureText: true,
                onChanged: (_) => setState(() {})),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                    child: TextField(
                        controller: _controllers['encryption'],
                        decoration: commonInputDec.copyWith(
                            labelText: "Encryption (WPA/WEP)"))),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _controllers['hidden']?.text,
                    items: const [
                      DropdownMenuItem(value: "false", child: Text("Visible")),
                      DropdownMenuItem(value: "true", child: Text("Hidden"))
                    ],
                    onChanged: (v) =>
                        setState(() => _controllers['hidden']?.text = v!),
                    decoration:
                        commonInputDec.copyWith(labelText: "Visibility"),
                  ),
                )
              ],
            )
          ],
        );
      case QrDataType.email:
        return Column(
          children: [
            TextField(
                controller: _controllers['email'],
                decoration: commonInputDec.copyWith(labelText: "Email Address"),
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) => setState(() {})),
            const SizedBox(height: 10),
            TextField(
                controller: _controllers['subject'],
                decoration: commonInputDec.copyWith(labelText: "Subject"),
                onChanged: (_) => setState(() {})),
            const SizedBox(height: 10),
            TextField(
                controller: _controllers['body'],
                decoration: commonInputDec.copyWith(labelText: "Message Body"),
                maxLines: 3,
                onChanged: (_) => setState(() {})),
          ],
        );
      case QrDataType.phone:
        return TextField(
            controller: _controllers['phone'],
            decoration: commonInputDec.copyWith(labelText: "Phone Number"),
            keyboardType: TextInputType.phone,
            onChanged: (_) => setState(() {}));
      case QrDataType.sms:
        return Column(
          children: [
            TextField(
                controller: _controllers['phone'],
                decoration: commonInputDec.copyWith(labelText: "Phone Number"),
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {})),
            const SizedBox(height: 10),
            TextField(
                controller: _controllers['body'],
                decoration: commonInputDec.copyWith(labelText: "Message"),
                maxLines: 3,
                onChanged: (_) => setState(() {})),
          ],
        );
      case QrDataType.vcard:
        return Column(
          children: [
            TextField(
                controller: _controllers['name'],
                decoration: commonInputDec.copyWith(labelText: "Full Name"),
                onChanged: (_) => setState(() {})),
            const SizedBox(height: 10),
            TextField(
                controller: _controllers['phone'],
                decoration: commonInputDec.copyWith(labelText: "Phone"),
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {})),
            const SizedBox(height: 10),
            TextField(
                controller: _controllers['email'],
                decoration: commonInputDec.copyWith(labelText: "Email"),
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) => setState(() {})),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                    child: TextField(
                        controller: _controllers['org'],
                        decoration:
                            commonInputDec.copyWith(labelText: "Company"),
                        onChanged: (_) => setState(() {}))),
                const SizedBox(width: 10),
                Expanded(
                    child: TextField(
                        controller: _controllers['title'],
                        decoration:
                            commonInputDec.copyWith(labelText: "Job Title"),
                        onChanged: (_) => setState(() {}))),
              ],
            )
          ],
        );
      case QrDataType.location:
        return Row(
          children: [
            Expanded(
                child: TextField(
                    controller: _controllers['lat'],
                    decoration: commonInputDec.copyWith(labelText: "Latitude"),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}))),
            const SizedBox(width: 10),
            Expanded(
                child: TextField(
                    controller: _controllers['long'],
                    decoration: commonInputDec.copyWith(labelText: "Longitude"),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}))),
          ],
        );
      case QrDataType.event:
        return Column(
          children: [
            TextField(
                controller: _controllers['event_title'],
                decoration: commonInputDec.copyWith(labelText: "Event Title"),
                onChanged: (_) => setState(() {})),
            const SizedBox(height: 10),
            TextField(
                controller: _controllers['event_loc'],
                decoration: commonInputDec.copyWith(labelText: "Location"),
                onChanged: (_) => setState(() {})),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text("Start: ",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                TextButton(
                    onPressed: () => _selectDate(context, true),
                    child:
                        Text(DateFormat('yyyy-MM-dd').format(_eventStartDate))),
                TextButton(
                    onPressed: () => _selectTime(context, true),
                    child: Text(_eventStartTime.format(context))),
              ],
            ),
            Row(
              children: [
                const Text("End:   ",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                TextButton(
                    onPressed: () => _selectDate(context, false),
                    child:
                        Text(DateFormat('yyyy-MM-dd').format(_eventEndDate))),
                TextButton(
                    onPressed: () => _selectTime(context, false),
                    child: Text(_eventEndTime.format(context))),
              ],
            ),
          ],
        );
      default:
        return TextField(
            controller: _controllers['text'],
            decoration: commonInputDec.copyWith(labelText: "Data"),
            onChanged: (_) => setState(() {}));
    }
  }

  void _pickColor(bool isForeground) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isForeground ? 'Foreground Color' : 'Background Color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: isForeground ? _fgColor : _bgColor,
            onColorChanged: (color) => setState(() {
              if (isForeground)
                _fgColor = color;
              else
                _bgColor = color;
            }),
            labelTypes: const [],
            pickerAreaHeightPercent: 0.8,
          ),
        ),
        actions: [
          TextButton(
              child: const Text('Done'),
              onPressed: () => Navigator.of(context).pop())
        ],
      ),
    );
  }
}
