import 'dart:convert';
import 'dart:io';

import 'package:cloudy/sync/remote_drive.dart';
import 'package:crypto/crypto.dart';

class _Node {
  _Node({
    required this.id,
    required this.name,
    required this.parentId,
    required this.isFolder,
    this.bytes,
    this.modifiedMs = 0,
  });

  final String id;
  String name;
  final String? parentId;
  final bool isFolder;
  List<int>? bytes;
  int modifiedMs;
  bool trashed = false;

  String? get md5Hash => bytes == null ? null : md5.convert(bytes!).toString();
}

/// Google Drive en memoria para las pruebas del motor de sincronización.
class FakeRemoteDrive implements RemoteDrive {
  FakeRemoteDrive() {
    _nodes[rootId] = _Node(
      id: rootId,
      name: '',
      parentId: null,
      isFolder: true,
    );
  }

  static const rootId = 'root';

  final Map<String, _Node> _nodes = {};
  int _nextId = 0;
  int _clock = 1000000;

  int uploadCount = 0;
  int downloadCount = 0;
  int trashCount = 0;

  /// Nombres de archivo cuya subida o descarga debe fallar.
  final Set<String> failingNames = {};

  // Utilidades para preparar y comprobar el estado en las pruebas.

  String putFile(String path, String content) {
    final segments = path.split('/');
    var parent = rootId;
    for (final name in segments.take(segments.length - 1)) {
      parent = _childFolder(parent, name) ?? _newFolder(parent, name).id;
    }
    final existing = _child(parent, segments.last);
    if (existing != null) {
      existing.bytes = utf8.encode(content);
      existing.modifiedMs = _tick();
      return existing.id;
    }
    final node = _Node(
      id: 'f${_nextId++}',
      name: segments.last,
      parentId: parent,
      isFolder: false,
      bytes: utf8.encode(content),
      modifiedMs: _tick(),
    );
    _nodes[node.id] = node;
    return node.id;
  }

  void deleteFile(String path) => _resolve(path)!.trashed = true;

  /// Contenido de todos los archivos visibles, por ruta.
  Map<String, String> files() {
    final result = <String, String>{};
    for (final node in _nodes.values) {
      if (node.isFolder || !_isVisible(node)) continue;
      result[_pathOf(node)] = utf8.decode(node.bytes!);
    }
    return result;
  }

  bool folderExists(String path) {
    final node = _resolve(path);
    return node != null && node.isFolder && _isVisible(node);
  }

  // Implementación de RemoteDrive.

  @override
  Future<RemoteTree> listTree(
    String rootId, {
    bool Function(String relativePath, bool isFolder)? include,
  }) async {
    final tree = RemoteTree(rootId: rootId);
    void walk(String folderId, String prefix) {
      for (final node in _children(folderId)) {
        final path = prefix.isEmpty ? node.name : '$prefix/${node.name}';
        if (include != null && !include(path, node.isFolder)) continue;
        if (node.isFolder) {
          tree.folders[path] = node.id;
          walk(node.id, path);
        } else {
          tree.files[path] = _toRemote(node);
        }
      }
    }

    walk(rootId, '');
    return tree;
  }

  @override
  Future<List<RemoteFolder>> listFolders(String parentId) async => [
    for (final node in _children(parentId))
      if (node.isFolder) RemoteFolder(id: node.id, name: node.name),
  ];

  @override
  Future<RemoteFolder> createFolder({
    required String parentId,
    required String name,
  }) async {
    final node = _newFolder(parentId, name);
    return RemoteFolder(id: node.id, name: node.name);
  }

  @override
  Future<RemoteFile> uploadNew({
    required String parentId,
    required String name,
    required File source,
  }) async {
    _maybeFail(name);
    final node = _Node(
      id: 'f${_nextId++}',
      name: name,
      parentId: parentId,
      isFolder: false,
      bytes: await source.readAsBytes(),
      modifiedMs: _tick(),
    );
    _nodes[node.id] = node;
    uploadCount++;
    return _toRemote(node);
  }

  @override
  Future<RemoteFile> uploadUpdate({
    required String fileId,
    required File source,
  }) async {
    final node = _nodes[fileId]!;
    _maybeFail(node.name);
    node.bytes = await source.readAsBytes();
    node.modifiedMs = _tick();
    uploadCount++;
    return _toRemote(node);
  }

  @override
  Future<void> download({required String fileId, required File target}) async {
    final node = _nodes[fileId]!;
    _maybeFail(node.name);
    await target.writeAsBytes(node.bytes!);
    downloadCount++;
  }

  @override
  Future<bool> isFolderEmpty(String folderId) async =>
      _children(folderId).isEmpty;

  @override
  Future<void> trash(String id) async {
    _nodes[id]!.trashed = true;
    trashCount++;
  }

  // Internos.

  int _tick() => _clock += 1000;

  void _maybeFail(String name) {
    if (failingNames.contains(name)) {
      throw RemoteException('fallo simulado en $name');
    }
  }

  Iterable<_Node> _children(String parentId) =>
      _nodes.values.where((n) => n.parentId == parentId && !n.trashed);

  _Node? _child(String parentId, String name) =>
      _children(parentId).where((n) => n.name == name).firstOrNull;

  String? _childFolder(String parentId, String name) {
    final node = _child(parentId, name);
    return node != null && node.isFolder ? node.id : null;
  }

  _Node _newFolder(String parentId, String name) {
    final node = _Node(
      id: 'd${_nextId++}',
      name: name,
      parentId: parentId,
      isFolder: true,
      modifiedMs: _tick(),
    );
    _nodes[node.id] = node;
    return node;
  }

  _Node? _resolve(String path) {
    _Node? node = _nodes[rootId];
    for (final name in path.split('/')) {
      node = _child(node!.id, name);
      if (node == null) return null;
    }
    return node;
  }

  bool _isVisible(_Node node) {
    _Node? current = node;
    while (current != null) {
      if (current.trashed) return false;
      current = current.parentId == null ? null : _nodes[current.parentId];
    }
    return true;
  }

  String _pathOf(_Node node) {
    final parts = <String>[];
    _Node? current = node;
    while (current != null && current.id != rootId) {
      parts.insert(0, current.name);
      current = _nodes[current.parentId];
    }
    return parts.join('/');
  }

  RemoteFile _toRemote(_Node node) => RemoteFile(
    id: node.id,
    name: node.name,
    size: node.bytes?.length ?? 0,
    md5: node.md5Hash,
    modifiedMs: node.modifiedMs,
  );
}
