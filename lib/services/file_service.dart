import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class FileService {
  static Future<String?> pickFile({List<String>? allowedExtensions}) async {
    try {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        throw Exception('Storage permission denied');
      }

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions ?? ['json'],
      );

      if (result != null && result.files.single.path != null) {
        return result.files.single.path!;
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  static Future<String?> saveFile(String fileName, String content) async {
    try {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        throw Exception('Storage permission denied');
      }

      String? path = await FilePicker.platform.saveFile(
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (path != null) {
        // Ensure .json extension
        if (!path.endsWith('.json')) {
          path = '$path.json';
        }
        final file = File(path);
        await file.writeAsString(content);
        return path;
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }
}
