import 'dart:io';

/// Archivo (no carpeta) en el almacenamiento remoto.
class RemoteFile {
  const RemoteFile({
    required this.id,
    required this.name,
    required this.size,
    required this.md5,
    required this.modifiedMs,
  });

  final String id;
  final String name;
  final int size;
  final String? md5;
  final int modifiedMs;
}

class RemoteFolder {
  const RemoteFolder({required this.id, required this.name});

  final String id;
  final String name;
}

/// Contenido completo (recursivo) de una carpeta remota.
class RemoteTree {
  RemoteTree({required String rootId}) : folders = {'': rootId};

  /// Archivos indexados por ruta relativa con `/` como separador.
  final Map<String, RemoteFile> files = {};

  /// Identificadores de carpetas por ruta relativa. `''` es la raíz.
  final Map<String, String> folders;

  /// Avisos no fatales producidos al listar (duplicados, nombres inválidos…).
  final List<String> warnings = [];
}

/// Error que impide continuar con toda la sincronización (credenciales
/// caducadas, sin conexión…), a diferencia de un error de un único archivo.
class FatalSyncException implements Exception {
  const FatalSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Error de una operación remota concreta (un archivo), con un mensaje legible.
class RemoteException implements Exception {
  const RemoteException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Operaciones que el motor de sincronización necesita del almacenamiento
/// remoto. Existe una implementación para Google Drive y otra en memoria para
/// las pruebas.
abstract class RemoteDrive {
  /// Lista recursivamente la carpeta [rootId]. [include] permite omitir rutas
  /// excluidas (para carpetas, se evita incluso recorrerlas).
  Future<RemoteTree> listTree(
    String rootId, {
    bool Function(String relativePath, bool isFolder)? include,
  });

  /// Subcarpetas directas de [parentId], para el selector de carpetas.
  Future<List<RemoteFolder>> listFolders(String parentId);

  Future<RemoteFolder> createFolder({
    required String parentId,
    required String name,
  });

  Future<RemoteFile> uploadNew({
    required String parentId,
    required String name,
    required File source,
  });

  Future<RemoteFile> uploadUpdate({
    required String fileId,
    required File source,
  });

  /// Descarga el contenido de [fileId] en [target] (sobrescribiéndolo).
  Future<void> download({required String fileId, required File target});

  /// Si la carpeta no contiene nada (ni siquiera archivos excluidos).
  Future<bool> isFolderEmpty(String folderId);

  /// Envía el archivo o carpeta a la papelera.
  Future<void> trash(String id);
}
