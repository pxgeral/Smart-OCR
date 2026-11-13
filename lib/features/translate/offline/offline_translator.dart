import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../translation_service.dart' show TranslationCancelled;
import 'marian_engine.dart';

/// Pembatal untuk penerjemahan offline yang sedang berjalan.
class OfflineCancel {
  bool _cancelled = false;
  void Function()? _hook;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _hook?.call();
  }
}

class _Job {
  const _Job(this.port, this.modelDir, this.texts, this.flagAddress);
  final SendPort port;
  final String modelDir;
  final List<String> texts;

  /// Alamat 1 byte memori native: bukan nol berarti batalkan.
  final int flagAddress;
}

class _Done {
  const _Done(this.texts);
  final List<String> texts;
}

class _Fail {
  const _Fail(this.message);
  final String message;
}

/// Menjalankan [MarianEngine] di isolate terpisah agar layar tidak membeku.
///
/// Pembatalan memakai penanda di memori native yang dibaca pekerja pada tiap
/// langkah, bukan mematikan isolate, supaya sesi ONNX selalu ditutup dan
/// memori model (±200 MB) dibebaskan.
class OfflineTranslator {
  static Future<List<String>> translateAll(
    String modelDir,
    List<String> texts, {
    void Function(int done)? onProgress,
    OfflineCancel? cancel,
  }) async {
    if (cancel?.isCancelled ?? false) throw const TranslationCancelled();
    final flag = calloc<ffi.Uint8>(); // sengaja tidak dibebaskan: 1 byte
    final port = ReceivePort();
    final result = Completer<List<String>>();
    cancel?._hook = () {
      flag.value = 1;
      if (!result.isCompleted) result.completeError(const TranslationCancelled());
    };
    await Isolate.spawn(
      _worker,
      _Job(port.sendPort, modelDir, texts, flag.address),
      onError: port.sendPort,
      onExit: port.sendPort,
    );
    final sub = port.listen((m) {
      if (result.isCompleted) return;
      if (m is int) {
        onProgress?.call(m);
      } else if (m is _Done) {
        result.complete(m.texts);
      } else if (m is _Fail) {
        result.completeError(StateError(m.message));
      } else if (m is List) {
        result.completeError(StateError('Mesin terjemahan berhenti: ${m.first}'));
      } else if (m == null) {
        result.completeError(StateError('Mesin terjemahan berhenti tak terduga'));
      }
    });
    try {
      return await result.future;
    } finally {
      cancel?._hook = null;
      // beri pekerja waktu menutup mesin sebelum port ditutup
      unawaited(Future<void>.delayed(const Duration(seconds: 5), () async {
        await sub.cancel();
        port.close();
      }));
    }
  }
}

void _worker(_Job job) {
  final flag = ffi.Pointer<ffi.Uint8>.fromAddress(job.flagAddress);
  bool cancelled() => flag.value != 0;
  MarianEngine? engine;
  try {
    engine = MarianEngine.open(job.modelDir);
    final out = <String>[];
    for (var i = 0; i < job.texts.length; i++) {
      if (cancelled()) throw StateError('dibatalkan');
      out.add(job.texts[i]
          .split('\n')
          .map((l) => RegExp(r'[A-Za-zÀ-ÿ]{2,}').hasMatch(l)
              ? translateLine(engine!, l, isCancelled: cancelled)
              : l)
          .join('\n'));
      job.port.send(i + 1);
    }
    job.port.send(_Done(out));
  } catch (e) {
    job.port.send(_Fail('$e'));
  } finally {
    engine?.close();
  }
}
