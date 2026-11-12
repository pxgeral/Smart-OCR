const xmlHeader = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';

final _illegal = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]');

/// Escape teks untuk isi/atribut XML dan buang karakter kontrol ilegal.
String xmlEscape(String s) => s
    .replaceAll(_illegal, '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
