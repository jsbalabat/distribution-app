import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class PickedExcelFile {
  PickedExcelFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

Future<Uint8List> _readAllBytes(Stream<List<int>> stream) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

Future<PickedExcelFile?> pickExcelFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
    withData: true,
    withReadStream: true,
  );

  if (result == null || result.files.isEmpty) {
    return null;
  }

  final selected = result.files.first;
  Uint8List? bytes = selected.bytes;

  if ((bytes == null || bytes.isEmpty) && selected.readStream != null) {
    bytes = await _readAllBytes(selected.readStream!);
  }

  // Some Android providers return only a file path; load bytes from disk.
  if ((bytes == null || bytes.isEmpty) && selected.path != null) {
    try {
      bytes = await File(selected.path!).readAsBytes();
    } catch (_) {
      // Leave bytes null; handled by final guard below.
    }
  }

  if (bytes == null || bytes.isEmpty) {
    throw Exception(
      'Selected file could not be read. Ensure storage permission and local file access are granted.',
    );
  }

  return PickedExcelFile(
    name: selected.name.isNotEmpty ? selected.name : 'upload.xlsx',
    bytes: bytes,
  );
}
