import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants.dart';
import 'features/history/history_screen.dart';
import 'features/ocr/settings_screen.dart';
import 'features/scanner/start_flow.dart';
import 'widgets/source_tab.dart';

class App extends StatelessWidget {
  const App({super.key});

  static const _seed = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: _seed, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: _seed,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _titles = ['Kamera', 'Galeri', 'PDF', 'Riwayat', 'Pengaturan'];
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_index])),
      body: IndexedStack(
        index: _index,
        children: [
          SourceTab(
            icon: Icons.document_scanner,
            title: 'Scan dokumen',
            subtitle:
                'Foto dokumen dengan deteksi tepi, crop, dan koreksi perspektif otomatis. Bisa banyak halaman.',
            buttonLabel: 'Scan baru',
            onStart: () => startFlow(context, ref, SourceKind.camera),
          ),
          SourceTab(
            icon: Icons.photo_library,
            title: 'Dari galeri',
            subtitle: 'Pilih satu atau beberapa foto/gambar untuk dikonversi.',
            buttonLabel: 'Pilih foto',
            onStart: () => startFlow(context, ref, SourceKind.gallery),
          ),
          SourceTab(
            icon: Icons.picture_as_pdf,
            title: 'Dari PDF',
            subtitle: 'PDF scan, foto, atau teks. Hingga 300 halaman.',
            buttonLabel: 'Pilih PDF',
            onStart: () => startFlow(context, ref, SourceKind.pdf),
          ),
          const HistoryScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.photo_camera), label: 'Kamera'),
          NavigationDestination(icon: Icon(Icons.photo_library), label: 'Galeri'),
          NavigationDestination(icon: Icon(Icons.picture_as_pdf), label: 'PDF'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Riwayat'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Pengaturan'),
        ],
      ),
    );
  }
}
