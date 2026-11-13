import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../../models/converted_content.dart';
import 'offline/model_assets.dart';
import 'offline/offline_translator.dart';

/// Terjemahan dokumen offline dengan model bawaan APK (Indonesia <-> Inggris).
/// Tanpa unduhan dan tanpa internet. Struktur, angka, tanggal, dan kotak
/// centang tidak diubah. Bahasa lain memakai [TranslationService] (ML Kit).
class OfflineTranslationService {
  static final _letters = RegExp(r'[A-Za-zÀ-ÿ]{2,}');

  final OfflineCancel _cancel = OfflineCancel();

  /// Nama folder model untuk pasangan bahasa, atau null bila tidak didukung.
  static String? directionFor(TranslateLanguage from, TranslateLanguage to) {
    if (from == TranslateLanguage.indonesian && to == TranslateLanguage.english) {
      return 'id-en';
    }
    if (from == TranslateLanguage.english && to == TranslateLanguage.indonesian) {
      return 'en-id';
    }
    return null;
  }

  /// true bila pasangan bahasa didukung dan modelnya ikut terkemas di aplikasi.
  static Future<bool> isAvailable(TranslateLanguage from, TranslateLanguage to) async {
    final d = directionFor(from, to);
    return d != null && await OfflineModelAssets.available(d);
  }

  void cancel() => _cancel.cancel();

  Future<ConvertedContent> translate(
    ConvertedContent source, {
    required TranslateLanguage from,
    required TranslateLanguage to,
    void Function(String message, double? progress)? onProgress,
    String? modelDirOverride,
  }) async {
    final direction = directionFor(from, to);
    if (direction == null) {
      throw StateError('Pasangan bahasa ini tidak tersedia offline.');
    }
    final modelDir = modelDirOverride ??
        await OfflineModelAssets.prepare(direction,
            onStatus: (m) => onProgress?.call(m, null));

    // salinan penuh agar teks asli tetap bisa dikembalikan
    final copy = ConvertedContent.fromMap(source.toMap());
    final texts = <String>{};
    for (final b in copy.blocks) {
      if (_letters.hasMatch(b.text)) texts.add(b.text);
    }
    for (final t in copy.tables) {
      for (final c in t.cells) {
        if (!c.numeric && _letters.hasMatch(c.text)) texts.add(c.text);
      }
    }

    final list = texts.toList();
    onProgress?.call('Memuat mesin terjemahan...', null);
    final translated = await OfflineTranslator.translateAll(
      modelDir,
      list,
      cancel: _cancel,
      onProgress: (done) => onProgress?.call(
          'Menerjemahkan $done/${list.length} (offline)', done / list.length),
    );
    final done = {for (var i = 0; i < list.length; i++) list[i]: translated[i]};

    for (final b in copy.blocks) {
      b.text = done[b.text] ?? b.text;
    }
    for (final t in copy.tables) {
      for (final c in t.cells) {
        c.text = done[c.text] ?? c.text;
      }
    }
    return copy;
  }
}
