import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: MangaCleanerMobileApp(),
  ));
}

class MangaCleanerMobileApp extends StatefulWidget {
  const MangaCleanerMobileApp({super.key});

  @override
  State<MangaCleanerMobileApp> createState() => _MangaCleanerMobileAppState();
}

class _MangaCleanerMobileAppState extends State<MangaCleanerMobileApp> {
  final TextEditingController _urlController = TextEditingController();
  File? _selectedImage;
  Uint8List? _cleanedImageBytes;
  bool _isLoading = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _loadSavedUrl();
  }

  // خواندن آخرین لینک کولب ذخیره شده
  Future<void> _loadSavedUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('colab_url') ?? '';
    setState(() {
      _urlController.text = savedUrl;
    });
  }

  // انتخاب عکس از گالری گوشی
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
        _cleanedImageBytes = null;
        _status = 'عکس انتخاب شد.';
      });
    }
  }

  // ارسال به گوگل کولب برای پاکسازی هوشمند متن
  Future<void> _sendToColab() async {
    final serverUrl = _urlController.text.trim();
    if (serverUrl.isEmpty || _selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لطفاً لینک کولب و عکس را انتخاب کنید')),
      );
      return;
    }

    // ذخیره آدرس برای دفعات بعد
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('colab_url', serverUrl);

    setState(() {
      _isLoading = true;
      _status = 'در حال ارسال و پاک‌سازی هوشمند در سرور کولب...';
    });

    try {
      final cleanUrl = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
      final uri = Uri.parse('$cleanUrl/api/predict/');

      final request = http.MultipartRequest('POST', uri);
      request.files.add(await http.MultipartFile.fromPath('data', _selectedImage!.path));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        // دریافت تصویر از نتیجه پاسخ کولب
        String base64String = decoded['data'][0];
        if (base64String.contains(',')) {
          base64String = base64String.split(',').last;
        }
        setState(() {
          _cleanedImageBytes = base64Decode(base64String);
          _status = 'پاک‌سازی با موفقیت انجام شد!';
        });
      } else {
        setState(() => _status = 'خطا از سرور: کد ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _status = 'خطا در ارتباط با کولب: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // تبدیل به فرمت کم‌حجم WebP و ذخیره در حافظه گوشی
  Future<void> _saveAsWebp() async {
    if (_cleanedImageBytes == null) return;

    try {
      final decodedImg = img.decodeImage(_cleanedImageBytes!);
      if (decodedImg == null) return;

      // تبدیل به فرمت WebP با کیفیت عالی
      final webpData = img.encodeWebP(decodedImg, quality: 85);

      final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      final filename = 'MangaCleaned_${DateTime.now().millisecondsSinceEpoch}.webp';
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(webpData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text('فایل WebP با موفقیت ذخیره شد:\n${file.path}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در ذخیره فایل: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Specter - پاک‌کننده هوشمند مانهوا'),
        backgroundColor: const Color(0xFF1E1E2E),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // فیلد ورود لینک کولب
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: 'لینک گوگل کولب (https://...gradio.live)',
                hintText: 'https://xxxx.gradio.live',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.link),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _urlController.clear(),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // دکمه انتخاب عکس
            ElevatedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.photo_library),
              label: const Text('انتخاب صفحه مانهوا از گالری'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 12),

            // دکمه ارسال به هوش مصنوعی
            ElevatedButton.icon(
              onPressed: (_selectedImage != null && !_isLoading) ? _sendToColab : null,
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('پاک‌سازی متن با هوش مصنوعی کولب'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 16),

            if (_status.isNotEmpty)
              Text(_status, style: const TextStyle(fontWeight: FontWeight.bold)),

            if (_isLoading) ...[
              const SizedBox(height: 20),
              const CircularProgressIndicator(),
            ],

            const SizedBox(height: 20),

            // پیش‌نمایش تصویر خروجی
            if (_cleanedImageBytes != null) ...[
              const Text('نتیجه پاک‌سازی شده:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(_cleanedImageBytes!),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _saveAsWebp,
                icon: const Icon(Icons.download),
                label: const Text('ذخیره تصویر به فرمت WebP'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ] else if (_selectedImage != null) ...[
              const Text('تصویر اصلی انتخاب شده:'),
              const SizedBox(height: 8),
              Image.file(_selectedImage!, height: 300),
            ],
          ],
        ),
      ),
    );
  }
}
