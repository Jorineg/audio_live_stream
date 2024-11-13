import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:math';

class DebugUtils {
  static Future<void> analyzeAppStorage() async {
    // App's private directory
    final appDir = await getApplicationDocumentsDirectory();
    final appSize = await _calculateDirSize(appDir);

    // Temp directory
    final tempDir = await getTemporaryDirectory();
    final tempSize = await _calculateDirSize(tempDir);

    // Cache directory
    final cacheDir = await getApplicationSupportDirectory();
    final cacheSize = await _calculateDirSize(cacheDir);

    print('''
    App Storage Analysis:
    -------------------
    Documents Dir: ${_formatSize(appSize)}
    Location: ${appDir.path}
    
    Temporary Dir: ${_formatSize(tempSize)}
    Location: ${tempDir.path}
    
    Cache Dir: ${_formatSize(cacheSize)}
    Location: ${cacheDir.path}
    ''');

    // List largest files
    await _listLargestFiles(appDir);
    await _listLargestFiles(tempDir);
    await _listLargestFiles(cacheDir);
  }

  static Future<int> _calculateDirSize(Directory dir) async {
    int totalSize = 0;
    try {
      if (await dir.exists()) {
        await for (var entity
            in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            totalSize += await entity.length();
          }
        }
      }
    } catch (e) {
      print('Error calculating size for ${dir.path}: $e');
    }
    return totalSize;
  }

  static String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
  }

  static Future<void> _listLargestFiles(Directory dir) async {
    List<MapEntry<String, int>> files = [];

    try {
      await for (var entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          files.add(MapEntry(entity.path, await entity.length()));
        }
      }

      // Sort by size descending
      files.sort((a, b) => b.value.compareTo(a.value));

      print('\nLargest files in ${dir.path}:');
      for (var file in files.take(5)) {
        print('${_formatSize(file.value)}: ${file.key}');
      }
    } catch (e) {
      print('Error listing files for ${dir.path}: $e');
    }
  }
}
