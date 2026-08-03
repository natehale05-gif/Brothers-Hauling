import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../data/ids.dart';

import '../models/job.dart';

/// How a driver is asked for a shot. Desktop has no camera worth using here, so
/// it falls through to the file picker.
enum PhotoSource { camera, gallery }

abstract class PhotoService {
  /// Returns null when the driver backs out of the picker.
  Future<JobPhoto?> capture(PhotoSource source);

  /// False on desktop, where [PhotoSource.camera] silently becomes a file pick.
  bool get supportsCamera;
}

class ImagePickerPhotoService implements PhotoService {
  ImagePickerPhotoService([ImagePicker? picker])
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  bool get supportsCamera {
    if (kIsWeb) return true; // getUserMedia
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  Future<JobPhoto?> capture(PhotoSource source) async {
    final wantsCamera = source == PhotoSource.camera && supportsCamera;
    final XFile? file = await _picker.pickImage(
      source: wantsCamera ? ImageSource.camera : ImageSource.gallery,
      // Job photos are evidence, not portfolio pieces. Cap them so a tablet on
      // a hotspot in Blodgett can still file one.
      maxWidth: 2000,
      imageQuality: 82,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (file == null) return null;

    // Bytes rather than a path: web has no readable file path, and holding the
    // bytes means one rendering path across all six platforms.
    final Uint8List bytes = await file.readAsBytes();
    return JobPhoto(id: ids.next('photo'), name: file.name, bytes: bytes);
  }
}

/// Hands back a 1x1 PNG without touching a platform channel.
class FakePhotoService implements PhotoService {
  FakePhotoService({this.cancel = false});

  /// When true, behaves like a driver dismissing the camera.
  bool cancel;

  int captures = 0;

  @override
  bool get supportsCamera => true;

  static final Uint8List _pixel = Uint8List.fromList(const [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);

  @override
  Future<JobPhoto?> capture(PhotoSource source) async {
    captures++;
    if (cancel) return null;
    return JobPhoto(
      id: 'photo-fake-$captures',
      name: 'shot-$captures.png',
      bytes: _pixel,
    );
  }
}
