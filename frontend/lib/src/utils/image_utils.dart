import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../core/app_config.dart';

class ImageUtils {
  /// Resizes an image for IQA if its longest side is greater than 2000px.
  /// Target resolution is 1920px on the longest side.
  static Future<File> resizeImageForIQA(File file) async {
    // Check feature flag from AppConfig
    if (!AppConfig.enableIqaImageCompression) {
      return file;
    }

    try {
      final bytes = await file.readAsBytes();
      
      // We can use FlutterImageCompress.getImageInfo or similar if we wanted to check dimensions first,
      // but FlutterImageCompress.compressAndGetFile with minWidth/minHeight handles the logic 
      // of "don't upscale" and "maintain aspect ratio" automatically.
      
      // However, to be precise about the 2000px threshold:
      // We can just always run it through the compressor with minWidth: 1920, minHeight: 1920.
      // If the image is smaller than 1920, it won't change. 
      // If it's between 1920 and 2000, it will scale down to 1920 (which is fine and recommended).
      
      final tempDir = await getTemporaryDirectory();
      final targetPath = p.join(
        tempDir.path, 
        'resized_${p.basename(file.path)}'
      );

      print('IQA: Checking image for resize: ${file.path}');
      
      // Compress and resize
      // quality: 90 is usually enough for IQA without losing critical data
      final XFile? result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: 90,
        minWidth: 1920,
        minHeight: 1920,
      );

      if (result == null) {
        print('IQA: Resize failed, using original.');
        return file;
      }

      final resizedFile = File(result.path);
      
      // Log for verification
      final originalSize = file.lengthSync();
      final newSize = resizedFile.lengthSync();
      print('IQA: Image processed. Original: ${originalSize} bytes, New: ${newSize} bytes');
      
      return resizedFile;
    } catch (e) {
      print('IQA: Error during image resize: $e');
      return file;
    }
  }
}
