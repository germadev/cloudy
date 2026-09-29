import 'dart:async';
import 'dart:io';

/// Impide que la app en primer plano y la tarea en segundo plano sincronicen
/// a la vez. Se basa en la creación exclusiva de un archivo, ya que los
/// bloqueos del sistema operativo no distinguen entre isolates del mismo
/// proceso. Mientras se mantiene, se actualiza su fecha periódicamente; si el
/// proceso muere, el bloqueo caduca solo.
class SyncLock {
  SyncLock(
    this.file, {
    this.staleAfter = const Duration(minutes: 5),
    this.heartbeat = const Duration(seconds: 30),
  });

  final File file;
  final Duration staleAfter;
  final Duration heartbeat;
  Timer? _timer;

  bool get isHeld => _timer != null;

  Future<bool> tryAcquire() async {
    if (isHeld) return false;
    if (!await _create()) {
      final stat = await file.stat();
      final age = DateTime.now().difference(stat.modified);
      if (stat.type != FileSystemEntityType.notFound && age < staleAfter) {
        return false;
      }
      try {
        await file.delete();
      } on FileSystemException {
        // Otro proceso lo ha borrado a la vez.
      }
      if (!await _create()) return false;
    }
    _timer = Timer.periodic(heartbeat, (_) {
      try {
        file.setLastModifiedSync(DateTime.now());
      } on FileSystemException {
        // Se reintentará en el siguiente latido.
      }
    });
    return true;
  }

  Future<void> release() async {
    _timer?.cancel();
    _timer = null;
    try {
      await file.delete();
    } on FileSystemException {
      // Ya no existía.
    }
  }

  Future<bool> _create() async {
    try {
      await file.parent.create(recursive: true);
      await file.create(exclusive: true);
      return true;
    } on FileSystemException {
      return false;
    }
  }
}
