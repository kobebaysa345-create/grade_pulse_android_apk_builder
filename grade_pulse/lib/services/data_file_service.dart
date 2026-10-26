import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'data_codec.dart';
import 'desktop_file_writer_stub.dart'
    if (dart.library.io) 'desktop_file_writer_io.dart';

/// What the user picked in the file chooser.
class PickedJsonFile {
  const PickedJsonFile({required this.name, required this.text});
  final String name;
  final String text;
}

/// The only place that talks to the device's file chooser / save dialog.
/// The UI depends on this interface, so tests can replace it and a future
/// change of file package touches this file only.
abstract class DataFileService {
  /// Lets the user choose a `.json` file. Returns null if they cancel.
  /// Throws [JsonDataException] if the file cannot be read.
  Future<PickedJsonFile?> pickJsonFile();

  /// Opens the platform save dialog. Returns true if saved, false if cancelled.
  Future<bool> saveJsonFile(String fileName, Uint8List bytes);
}

class DeviceDataFileService implements DataFileService {
  const DeviceDataFileService();

  static const int maxBytes = 5 * 1024 * 1024;

  @override
  Future<PickedJsonFile?> pickJsonFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    final Uint8List? bytes = file.bytes;
    if (bytes == null) {
      throw const JsonDataException(
        'The selected file could not be read. Try copying it to local storage and choosing it again.',
      );
    }
    if (bytes.length > maxBytes) {
      throw const JsonDataException(
        'The selected file is too large to be a Grade Pulse backup (limit 5 MB).',
      );
    }
    try {
      return PickedJsonFile(name: file.name, text: utf8.decode(bytes));
    } on FormatException {
      throw const JsonDataException(
        'The file is not valid UTF-8 text, so it is not a JSON file.',
      );
    }
  }

  @override
  Future<bool> saveJsonFile(String fileName, Uint8List bytes) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Grade Pulse data',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: bytes,
    );
    // On the web the browser downloads the file and no path is returned.
    if (kIsWeb) return true;
    if (path == null) return false; // cancelled
    await writeDesktopFileIfNeeded(path, bytes);
    return true;
  }
}
