import 'dart:async';
import 'dart:io';

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

/// Dilempar saat pengguna membatalkan unduhan model atau penerjemahan.
class TranslationCancelled implements Exception {
  const TranslationCancelled();
  @override
  String toString() => 'Penerjemahan dibatalkan';
}

/// Terjemahan dokumen di perangkat (Google ML Kit). Model tiap bahasa
/// (~30 MB) diunduh sekali saat pertama dipakai; setelah itu offline.
/// Struktur, angka, tanggal, dan kotak centang tidak diubah.
class TranslationService {
  static final _letters = RegExp(r'[A-Za-zÀ-ÿ]{2,}');

  static const _downloadTimeout = Duration(minutes: 5);

  final _models = OnDeviceTranslatorModelManager();
  bool _cancelled = false;

  /// Batalkan unduhan model / penerjemahan yang sedang berjalan.
  void cancel() => _cancelled = true;

  void _checkCancelled() {
    if (_cancelled) throw const TranslationCancelled();
  }

  Future<bool> _hasInternet() async {
    try {
      final r = await InternetAddress.lookup('dl.google.com')
          .timeout(const Duration(seconds: 6));
      return r.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Pastikan model bahasa ada. Unduhan diberi batas waktu, bisa dibatalkan,
  /// menampilkan waktu berjalan, dan dianggap selesai begitu model terdeteksi
  /// (unduhan kadang selesai tanpa mengembalikan hasil).
  Future<void> _ensureModel(TranslateLanguage l,
      void Function(String message, double? progress)? onProgress) async {
    final name = translateLanguages[l] ?? l.name;
    if (await _models.isModelDownloaded(l.bcpCode)) return;

    onProgress?.call('Memeriksa koneksi internet...', null);
    if (!await _hasInternet()) {
      throw StateError('Tidak ada koneksi internet untuk mengunduh model bahasa '
          '$name. Sambungkan internet lalu coba lagi.');
    }

    var finished = false;
    var succeeded = false;
    Object? failure;
    unawaited(_models
        .downloadModel(l.bcpCode, isWifiRequired: false)
        .then((ok) {
      succeeded = ok;
      finished = true;
    }, onError: (Object e) {
      failure = e;
      finished = true;
    }));

    final watch = Stopwatch()..start();
    while (true) {
      await Future<void>.delayed(const Duration(seconds: 1));
      _checkCancelled();
      final sec = watch.elapsed.inSeconds;
      if (finished) {
        if (failure != null) {
          throw StateError('Model bahasa $name gagal diunduh: $failure');
        }
        if (succeeded || await _models.isModelDownloaded(l.bcpCode)) return;
        throw StateError('Model bahasa $name gagal diunduh. Periksa koneksi '
            'internet dan ruang penyimpanan.');
      }
      if (sec % 3 == 0 && await _models.isModelDownloaded(l.bcpCode)) return;
      if (watch.elapsed > _downloadTimeout) {
        throw StateError('Unduhan model bahasa $name tidak selesai dalam '
            '${_downloadTimeout.inMinutes} menit. Periksa internet dan Google '
            'Play Services, lalu coba lagi.');
      }
      onProgress?.call(
          sec < 45
              ? 'Mengunduh model bahasa $name... $sec dtk'
              : 'Masih mengunduh model bahasa $name... $sec dtk (±30 MB). '
                  'Pastikan internet stabil, atau tekan Batal.',
          null);
    }
  }

  Future<bool> isReady(TranslateLanguage l) => _models.isModelDownloaded(l.bcpCode);

  Future<ConvertedContent> translate(
    ConvertedContent source, {
    required TranslateLanguage from,
    required TranslateLanguage to,
    void Function(String message, double? progress)? onProgress,
  }) async {
    _cancelled = false;
    for (final l in {from, to}) {
      await _ensureModel(l, onProgress);
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
        _checkCancelled();
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
