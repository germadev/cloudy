import 'package:cloudy/sync/path_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('excluye archivos ocultos salvo que se pidan', () {
    expect(PathFilter().includes('.git/config'), isFalse);
    expect(PathFilter().includes('fotos/.nomedia'), isFalse);
    expect(PathFilter(includeHidden: true).includes('fotos/.nomedia'), isTrue);
  });

  test('excluye siempre los temporales de descarga', () {
    final filter = PathFilter(includeHidden: true);
    expect(filter.includes('a.jpg${PathFilter.partialSuffix}'), isFalse);
  });

  test('un patrón sin barra se aplica a cualquier componente', () {
    final filter = PathFilter(excludePatterns: ['*.tmp', 'node_modules']);
    expect(filter.includes('a.tmp'), isFalse);
    expect(filter.includes('x/y/b.TMP'), isFalse);
    expect(filter.includes('proyecto/node_modules/lib/index.js'), isFalse);
    expect(filter.includes('proyecto/src/index.js'), isTrue);
  });

  test('un patrón con barra se aplica a la ruta completa', () {
    final filter = PathFilter(excludePatterns: ['fotos/*.raw', 'docs/tmp']);
    expect(filter.includes('fotos/img.raw'), isFalse);
    expect(filter.includes('otras/fotos/img.raw'), isTrue);
    expect(filter.includes('fotos/img.jpg'), isTrue);
    expect(filter.includes('docs/tmp/a.txt'), isFalse);
    expect(filter.includes('docs/tmp2/a.txt'), isTrue);
  });

  test('una barra final se ignora', () {
    final filter = PathFilter(excludePatterns: ['build/']);
    expect(filter.includes('build/out.bin'), isFalse);
    expect(filter.includes('app/build/out.bin'), isFalse);
    expect(filter.includes('building.txt'), isTrue);
  });

  test('? equivale a un carácter', () {
    final filter = PathFilter(excludePatterns: ['img?.jpg']);
    expect(filter.includes('img1.jpg'), isFalse);
    expect(filter.includes('img10.jpg'), isTrue);
  });

  test('interpreta la lista escrita por el usuario', () {
    expect(PathFilter.parsePatterns(' *.tmp, cache ,\nThumbs.db,, '), [
      '*.tmp',
      'cache',
      'Thumbs.db',
    ]);
  });
}
