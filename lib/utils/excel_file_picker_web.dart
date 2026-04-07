// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

class PickedExcelFile {
  PickedExcelFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

Future<PickedExcelFile?> pickExcelFile() async {
  final uploadInput = html.FileUploadInputElement();
  uploadInput.accept = '.xlsx';
  uploadInput.multiple = false;

  final completer = Completer<PickedExcelFile?>();

  uploadInput.onChange.listen((_) {
    final file = uploadInput.files?.isNotEmpty == true
        ? uploadInput.files!.first
        : null;
    if (file == null) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }

    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);

    reader.onLoadEnd.listen((_) {
      final result = reader.result;
      if (result is ByteBuffer) {
        final bytes = Uint8List.view(result);
        if (!completer.isCompleted) {
          completer.complete(PickedExcelFile(name: file.name, bytes: bytes));
        }
      } else if (result is Uint8List) {
        if (!completer.isCompleted) {
          completer.complete(PickedExcelFile(name: file.name, bytes: result));
        }
      } else if (result is List<int>) {
        final bytes = Uint8List.fromList(result);
        if (!completer.isCompleted) {
          completer.complete(PickedExcelFile(name: file.name, bytes: bytes));
        }
      } else {
        if (!completer.isCompleted) completer.complete(null);
      }
    });

    reader.onError.listen((_) {
      if (!completer.isCompleted) completer.complete(null);
    });
  });

  uploadInput.click();
  return completer.future;
}
