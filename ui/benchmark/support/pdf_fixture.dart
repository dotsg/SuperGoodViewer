import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Deterministic fixtures: one 800x40000pt page, with text/vector content or
/// repeated raster image strips. The latter is synthetic, not a real scan.
Uint8List makeBenchmarkPdf({bool scanned = false}) {
  final content = StringBuffer();
  if (scanned) {
    for (var y = 0; y < 40000; y += 1200) {
      content.writeln('q 800 0 0 1200 0 $y cm /Im0 Do Q');
    }
  } else {
    for (var y = 20; y < 40000; y += 18) {
      content.writeln('BT /F1 12 Tf 30 $y Td (Line $y: PDF raster benchmark - text and vectors 0123456789) Tj ET');
      content.writeln('0.4 0.5 0.6 RG 0.4 w 30 ${y - 3} m 760 ${y - 3} l S');
    }
  }
  Uint8List stream(List<int> bytes, [String dictionary = '']) {
    final compressed = zlib.encode(bytes);
    return Uint8List.fromList([
      ...ascii.encode('<< /Length ${compressed.length} /Filter /FlateDecode $dictionary >>\nstream\n'),
      ...compressed,
      ...ascii.encode('\nendstream'),
    ]);
  }

  final objects = <List<int>>[
    ascii.encode('<< /Type /Catalog /Pages 2 0 R >>'),
    ascii.encode('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
    ascii.encode(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 800 40000] '
      '/Resources << /Font << /F1 5 0 R >> ${scanned ? '/XObject << /Im0 6 0 R >>' : ''} >> /Contents 4 0 R >>',
    ),
    stream(ascii.encode(content.toString())),
    ascii.encode('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'),
  ];
  if (scanned) {
    const width = 1600, height = 2400;
    final pixels = Uint8List(width * height * 3);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 3;
        final ink = y % 36 < 17 && x % 23 < 14;
        final shade = ink ? 20 + (x + y) % 25 : 230 + (x * 7 + y * 3) % 26;
        pixels[i] = pixels[i + 1] = pixels[i + 2] = shade;
      }
    }
    objects.add(
      stream(
        pixels,
        '/Type /XObject /Subtype /Image /Width $width /Height $height /ColorSpace /DeviceRGB /BitsPerComponent 8',
      ),
    );
  }
  final result = BytesBuilder()..add(ascii.encode('%PDF-1.7\n'));
  final offsets = <int>[0];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(result.length);
    result.add(ascii.encode('${i + 1} 0 obj\n'));
    result.add(objects[i]);
    result.add(ascii.encode('\nendobj\n'));
  }
  final xref = result.length;
  result.add(ascii.encode('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n'));
  for (final offset in offsets.skip(1)) {
    result.add(ascii.encode('${offset.toString().padLeft(10, '0')} 00000 n \n'));
  }
  result.add(ascii.encode('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n'));
  return result.takeBytes();
}
