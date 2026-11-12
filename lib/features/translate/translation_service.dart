import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../../models/converted_content.dart';

/// Bahasa yang ditawarkan di aplikasi (nama tampilan Indonesia).
const translateLanguages = <TranslateLanguage, String>{
  TranslateLanguage.indonesian: 'Indonesia',
  TranslateLanguage.english: 'Inggris',
  TranslateLanguage.malay: 'Melayu',
  TranslateLanguage.arabic: 'Arab',
  TranslateLanguage.chinese: 'Mandarin',
  TranslateLanguage.japanese: 'Jepang',
  TranslateLanguage.korean: 'Korea',
  TranslateLanguage.dutch: 'Belanda',
  TranslateLanguage.german: 'Jerman',
  TranslateLanguage.french: 'Prancis',
  TranslateLanguage.spanish: 'Spanyol',
  TranslateLanguage.thai: 'Thai',
  TranslateLanguage.vietnamese: 'Vietnam',
  TranslateLanguage.hindi: 'Hindi',
  TranslateLanguage.tagalog: 'Tagalog',
};

/// Terjemahan dokumen di perangkat (Google ML Kit). Model tiap bahasa
/// (~30 MB) diunduh sekali saat pertama dipakai; setelah itu offline.
/// Struktur, angka, tanggal, dan kotak centang tidak diubah.
class TranslationService {
  static final _letters = RegExp(r'[A-Za-zÀ-ÿ]{2,}');

  final _models = OnDeviceTranslatorModelManager();

  Future<bool> isReady(TranslateLanguage l) => _models.isModelDownloaded(l.bcpCode);

  Future<ConvertedContent> translate(
    ConvertedContent source, {
    required TranslateLanguage from,
    required TranslateLanguage to,
    void Function(String message, double? progress)? onProgress,
  }) async {
    for (final l in {from, to}) {
      if (!await _models.isModelDownloaded(l.bcpCode)) {
        onProgress?.call('Mengunduh model bahasa ${translateLanguages[l] ?? l.name}...', null);
        final ok = await _models.downloadModel(l.bcpCode, isWifiRequired: false);
        if (!ok) {
          throw StateError('Model bahasa ${translateLanguages[l] ?? l.name} gagal diunduh. Periksa koneksi internet.');
        }
      }
    }

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

    final translator = OnDeviceTranslator(sourceLanguage: from, targetLanguage: to);
    final done = <String, String>{};
    try {
      var i = 0;
      for (final text in texts) {
        i++;
        onProgress?.call('Menerjemahkan $i/${texts.length}', i / texts.length);
        final lines = text.split('\n');
        final out = <String>[];
        for (final line in lines) {
          out.add(_letters.hasMatch(line) ? (await translator.translateText(line)).trim() : line);
        }
        done[text] = out.join('\n');
      }
    } finally {
      await translator.close();
    }

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
