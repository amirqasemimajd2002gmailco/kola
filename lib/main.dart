import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: MangaCleanerApp(),
  ));
}

// ساختار هر خط کشیده شده
class Stroke {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;

  Stroke({
    required this.points,
    required this.color,
    required this.strokeWidth,
  });
}

class MangaCleanerApp extends StatefulWidget {
  const MangaCleanerApp({super.key});

  @override
  State<MangaCleanerApp> createState() => _MangaCleanerAppState();
}

class _MangaCleanerAppState extends State<MangaCleanerApp> {
  File? _imageFile;
  img.Image? _rawImage;
  ui.Image? _displayImage;

  Color _selectedColor = Colors.white;
  double _brushSize = 25.0;
  bool _isEyedropper = false;
  bool _isSaving = false;

  final List<Stroke> _strokes = [];
  List<Offset> _currentPoints = [];

  // انتخاب تصویر از ویندوز
  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();

      final decodedRaw = img.decodeImage(bytes);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();

      setState(() {
        _imageFile = file;
        _rawImage = decodedRaw;
        _displayImage = frame.image;
        _strokes.clear();
        _currentPoints.clear();
      });
    }
  }

  // نمونه‌برداری رنگ زمینه (قطره‌چکان)
  void _pickColorAt(Offset localPos, Size renderSize) {
    if (_rawImage == null) return;

    // تبدیل مختصات صفحه نمایش به پیکسل واقعی عکس
    double scaleX = _rawImage!.width / renderSize.width;
    double scaleY = _rawImage!.height / renderSize.height;

    int px = (localPos.dx * scaleX).clamp(0, _rawImage!.width - 1).toInt();
    int py = (localPos.dy * scaleY).clamp(0, _rawImage!.height - 1).toInt();

    final pixel = _rawImage!.getPixel(px, py);

    setState(() {
      _selectedColor = Color.fromARGB(
        pixel.a.toInt(),
        pixel.r.toInt(),
        pixel.g.toInt(),
        pixel.b.toInt(),
      );
      _isEyedropper = false; // بعد از انتخاب رنگ، به حالت قلم برمی‌گردد
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('رنگ زمینه انتخاب شد!'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // ذخیره تصویر پاک‌سازی شده به عنوان WebP با کیفیت بالا
  Future<void> _exportToWebP(Size displaySize) async {
    if (_rawImage == null || _imageFile == null) return;

    setState(() => _isSaving = true);

    try {
      // کشیدن تغییرات روی یک بوم با ابعاد اصلی عکس
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, _rawImage!.width.toDouble(), _rawImage!.height.toDouble()),
      );

      // رسم تصویر اولیه
      canvas.drawImage(_displayImage!, Offset.zero, Paint());

      // ضریب تبدیل خطوط کشیده شده به اندازه واقعی عکس
      double scaleX = _rawImage!.width / displaySize.width;
      double scaleY = _rawImage!.height / displaySize.height;

      for (var stroke in _strokes) {
        final paint = Paint()
          ..color = stroke.color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = stroke.strokeWidth * scaleX
          ..isAntiAlias = true;

        for (int i = 0; i < stroke.points.length - 1; i++) {
          final p1 = Offset(stroke.points[i].dx * scaleX, stroke.points[i].dy * scaleY);
          final p2 = Offset(stroke.points[i + 1].dx * scaleX, stroke.points[i + 1].dy * scaleY);
          canvas.drawLine(p1, p2, paint);
        }
      }

      final picture = recorder.endRecording();
      final finalUiImg = await picture.toImage(_rawImage!.width, _rawImage!.height);
      final byteData = await finalUiImg.toByteData(format: ui.ImageByteFormat.png);
      final buffer = byteData!.buffer.asUint8List();

      // تبدیل به WebP با کیفیت عالی
      final imgToEncode = img.decodePng(buffer)!;
      final webpBytes = img.encodeWebP(imgToEncode, quality: 85);

      // مسیر ذخیره در Downloads سیستم
      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final filename = 'Cleaned_${DateTime.now().millisecondsSinceEpoch}.webp';
      final savePath = '${dir.path}\\$filename';

      final outFile = File(savePath);
      await outFile.writeAsBytes(webpBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green[700],
            content: Text('فایل WebP با موفقیت ذخیره شد:\n$savePath'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در ذخیره‌سازی: $e')),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF181825),
        title: const Text('Manga Cleaner - تبدیل و پاکسازی سریع به WebP'),
        actions: [
          if (_displayImage != null)
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                onPressed: _isSaving
                    ? null
                    : () => _exportToWebP(
                          // اندازه صفحه ویرایشگر
                          MediaQuery.of(context).size,
                        ),
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.download, color: Colors.white),
                label: const Text('خروجی WebP', style: TextStyle(color: Colors.white)),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // نوار ابزار بالا
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF252538),
            child: Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('انتخاب عکس مانهوا'),
                ),
                const SizedBox(width: 16),

                // دکمه قطره‌چکان
                IconButton(
                  tooltip: 'قطره‌چکان (انتخاب رنگ زمینه با کلیک روی عکس)',
                  icon: Icon(
                    Icons.colorize,
                    color: _isEyedropper ? Colors.amber : Colors.white,
                  ),
                  onPressed: _displayImage == null
                      ? null
                      : () => setState(() => _isEyedropper = !_isEyedropper),
                ),

                // نمایش رنگ انتخاب شده
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _selectedColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white38, width: 2),
                  ),
                ),
                const SizedBox(width: 20),

                // تنظیم اندازه قلم
                const Text('ضخامت قلم:', style: TextStyle(color: Colors.white70)),
                SizedBox(
                  width: 140,
                  child: Slider(
                    value: _brushSize,
                    min: 5.0,
                    max: 80.0,
                    onChanged: (val) => setState(() => _brushSize = val),
                  ),
                ),
                const Spacer(),

                // دکمه بازگشت (Undo)
                IconButton(
                  tooltip: 'بازگشت به حرکت قبل (Undo)',
                  icon: const Icon(Icons.undo, color: Colors.white),
                  onPressed: _strokes.isEmpty
                      ? null
                      : () => setState(() => _strokes.removeLast()),
                ),
                // دکمه پاک کردن کل خطوط
                IconButton(
                  tooltip: 'پاک کردن همه تغییرات',
                  icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
                  onPressed: _strokes.isEmpty ? null : () => setState(() => _strokes.clear()),
                ),
              ],
            ),
          ),

          // محوطه رسم و نمایش عکس
          Expanded(
            child: Center(
              child: _displayImage == null
                  ? const Text(
                      'برای شروع، یک عکس مانهوا انتخاب کنید',
                      style: TextStyle(color: Colors.white54, fontSize: 16),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        // حفظ نسبت ابعاد عکس در صفحه
                        double imgAspect = _displayImage!.width / _displayImage!.height;
                        double containerAspect = constraints.maxWidth / constraints.maxHeight;

                        double renderW, renderH;
                        if (containerAspect > imgAspect) {
                          renderH = constraints.maxHeight;
                          renderW = renderH * imgAspect;
                        } else {
                          renderW = constraints.maxWidth;
                          renderH = renderW / imgAspect;
                        }

                        Size renderSize = Size(renderW, renderH);

                        return GestureDetector(
                          onTapDown: (details) {
                            if (_isEyedropper) {
                              _pickColorAt(details.localPosition, renderSize);
                            }
                          },
                          onPanStart: (details) {
                            if (_isEyedropper) return;
                            _currentPoints = [details.localPosition];
                          },
                          onPanUpdate: (details) {
                            if (_isEyedropper) return;
                            setState(() {
                              _currentPoints.add(details.localPosition);
                            });
                          },
                          onPanEnd: (details) {
                            if (_isEyedropper) return;
                            setState(() {
                              _strokes.add(
                                Stroke(
                                  points: List.from(_currentPoints),
                                  color: _selectedColor,
                                  strokeWidth: _brushSize,
                                ),
                              );
                              _currentPoints.clear();
                            });
                          },
                          child: SizedBox(
                            width: renderW,
                            height: renderH,
                            child: CustomPaint(
                              painter: CleanerCanvasPainter(
                                image: _displayImage!,
                                strokes: _strokes,
                                activePoints: _currentPoints,
                                activeColor: _selectedColor,
                                activeBrushSize: _brushSize,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// نقاش برای رندر زنده روی صفحه مانیتور
class CleanerCanvasPainter extends CustomPainter {
  final ui.Image image;
  final List<Stroke> strokes;
  final List<Offset> activePoints;
  final Color activeColor;
  final double activeBrushSize;

  CleanerCanvasPainter({
    required this.image,
    required this.strokes,
    required this.activePoints,
    required this.activeColor,
    required this.activeBrushSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // رسم خود تصویر مانهوا
    paintImage(
      canvas: canvas,
      rect: Rect.fromLTWH(0, 0, size.width, size.height),
      image: image,
      fit: BoxFit.fill,
    );

    // رسم خطوط ذخیره شده قبلی
    for (var stroke in strokes) {
      final paint = Paint()
        ..color = stroke.color
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = stroke.strokeWidth
        ..isAntiAlias = true;

      for (int i = 0; i < stroke.points.length - 1; i++) {
        canvas.drawLine(stroke.points[i], stroke.points[i + 1], paint);
      }
    }

    // رسم خطی که در همین لحظه موس در حال کشیدن آن است
    if (activePoints.length > 1) {
      final activePaint = Paint()
        ..color = activeColor
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = activeBrushSize
        ..isAntiAlias = true;

      for (int i = 0; i < activePoints.length - 1; i++) {
        canvas.drawLine(activePoints[i], activePoints[i + 1], activePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
