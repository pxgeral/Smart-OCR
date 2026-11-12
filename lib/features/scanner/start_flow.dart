import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/providers.dart';
import '../converter/process_screen.dart';

enum SourceKind { camera, gallery, pdf }

/// Ambil sumber -> buka layar proses.
Future<void> startFlow(
  BuildContext context,
  WidgetRef ref,
  SourceKind kind,
) async {
  final scanner = ref.read(scannerServiceProvider);
  final result = switch (kind) {
    SourceKind.camera => await scanner.scanWithCamera(),
    SourceKind.gallery => await scanner.pickImages(),
    SourceKind.pdf => await scanner.pickPdf(),
  };
  if (!context.mounted) return;
  result.when<void>(
    ok: (req) {
      if (req == null) return;
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ProcessScreen(request: req),
      ));
    },
    err: (f) => ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(f.message))),
  );
}
