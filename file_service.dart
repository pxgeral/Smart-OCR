import 'dart:io';

import 'package:image_picker/image_picker.dart' show XFile;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class FileService {
  /// Subfolder di dokumen aplikasi (permanen) atau cache (sementara).
  Future<Directory> subDir(String name, {bool temp = false}) async {
    final base = temp
        ? await getTemporaryDirectory()
        : await getApplicationDocumentsDirectory();
    return Directory('${base.path}/$name').create(recursive: true);
  }

  /// Pilihan WhatsApp / Telegram / Gmail / Drive muncul dari share sheet Android.
  Future<void> share(String path) async {
    await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
  }

  Future<void> open(String path) async {
    await OpenFilex.open(path);
  }
}
