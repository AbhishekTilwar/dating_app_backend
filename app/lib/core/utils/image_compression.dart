import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart'; // XFile

/// Target max size in bytes (~100–120 KB) for profile photos.
const int kMaxImageBytes = 120 * 1024;

/// KYC selfie target (~80 KB).
const int kKycMaxBytes = 80 * 1024;

/// Compresses an image to a small JPEG for Storage upload.
Future<Uint8List> compressForUpload(XFile file) async {
  final bytes = await file.readAsBytes();
  return compressBytesForUpload(bytes, maxBytes: kMaxImageBytes);
}

/// Compresses image bytes to stay under [maxBytes].
Future<Uint8List> compressBytesForUpload(
  Uint8List bytes, {
  int maxBytes = kMaxImageBytes,
  int maxWidth = 1024,
  int maxHeight = 1024,
  int minQuality = 25,
}) async {
  int quality = 72;
  Uint8List result = await FlutterImageCompress.compressWithList(
    bytes,
    minWidth: maxWidth,
    minHeight: maxHeight,
    quality: quality,
    format: CompressFormat.jpeg,
  );
  while (result.length > maxBytes && quality > minQuality) {
    quality -= 10;
    if (quality < minQuality) quality = minQuality;
    result = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: maxWidth,
      minHeight: maxHeight,
      quality: quality,
      format: CompressFormat.jpeg,
    );
  }
  return result;
}
