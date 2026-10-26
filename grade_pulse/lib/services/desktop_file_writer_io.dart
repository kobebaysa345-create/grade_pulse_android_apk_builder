import 'dart:io';
import 'dart:typed_data';

/// On Windows, macOS and Linux the save dialog only returns the chosen path,
/// so the bytes are written here. Android and iOS write the file inside the
/// plugin, so they are left alone.
Future<void> writeDesktopFileIfNeeded(String path, Uint8List bytes) async {
  if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
  await File(path).writeAsBytes(bytes, flush: true);
}
