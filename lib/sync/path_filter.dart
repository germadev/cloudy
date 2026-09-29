/// Decide qué rutas relativas participan en la sincronización.
///
/// Los patrones admiten `*` (cualquier secuencia salvo `/`) y `?` (un único
/// carácter). Un patrón sin `/` se compara con cada componente de la ruta, de
/// modo que `node_modules` excluye esa carpeta a cualquier profundidad y
/// `*.tmp` cualquier archivo temporal. Un patrón con `/` se compara con la
/// ruta relativa desde la raíz (y excluye también el contenido de la carpeta
/// que coincida). Una `/` final se ignora.
class PathFilter {
  PathFilter({
    List<String> excludePatterns = const [],
    this.includeHidden = false,
  }) : _patterns = [
         for (final raw in excludePatterns)
           if (raw.trim().isNotEmpty) _Pattern(raw.trim()),
       ];

  /// Sufijo de los archivos temporales que se crean durante las descargas.
  static const partialSuffix = '.cloudy-part';

  final bool includeHidden;
  final List<_Pattern> _patterns;

  /// Convierte el texto introducido por el usuario (separado por comas o
  /// saltos de línea) en una lista de patrones.
  static List<String> parsePatterns(String text) => text
      .split(RegExp(r'[,\n]'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();

  bool includes(String relativePath) {
    final segments = relativePath.split('/');
    if (segments.last.endsWith(partialSuffix)) return false;
    if (!includeHidden && segments.any((s) => s.startsWith('.'))) return false;
    for (final pattern in _patterns) {
      if (pattern.hasSlash) {
        for (var i = 1; i <= segments.length; i++) {
          if (pattern.matches(segments.take(i).join('/'))) return false;
        }
      } else if (segments.any(pattern.matches)) {
        return false;
      }
    }
    return true;
  }
}

class _Pattern {
  factory _Pattern(String source) {
    final glob = source.endsWith('/')
        ? source.substring(0, source.length - 1)
        : source;
    return _Pattern._(
      glob.contains('/'),
      RegExp('^${_toRegex(glob)}\$', caseSensitive: false),
    );
  }

  _Pattern._(this.hasSlash, this._regex);

  final bool hasSlash;
  final RegExp _regex;

  bool matches(String value) => _regex.hasMatch(value);

  static String _toRegex(String glob) {
    final buffer = StringBuffer();
    for (final char in glob.split('')) {
      switch (char) {
        case '*':
          buffer.write('[^/]*');
        case '?':
          buffer.write('[^/]');
        default:
          buffer.write(RegExp.escape(char));
      }
    }
    return buffer.toString();
  }
}
