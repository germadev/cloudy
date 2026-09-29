import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../sync/remote_drive.dart';

/// Carpeta de Drive elegida por el usuario.
class DriveFolderSelection {
  const DriveFolderSelection({required this.id, required this.path});

  final String id;

  /// Ruta legible, p. ej. «Mi unidad/Fotos/2026».
  final String path;
}

/// Explorador de carpetas de «Mi unidad» para elegir el destino.
class DriveFolderPickerScreen extends StatefulWidget {
  const DriveFolderPickerScreen({super.key, this.suggestedName});

  /// Nombre propuesto al crear una carpeta nueva.
  final String? suggestedName;

  @override
  State<DriveFolderPickerScreen> createState() =>
      _DriveFolderPickerScreenState();
}

class _DriveFolderPickerScreenState extends State<DriveFolderPickerScreen> {
  late final RemoteDrive _remote = context.read<AuthService>().createRemote();
  final List<RemoteFolder> _stack = [
    const RemoteFolder(id: 'root', name: 'Mi unidad'),
  ];
  List<RemoteFolder>? _children;
  Object? _error;

  RemoteFolder get _current => _stack.last;
  String get _currentPath => _stack.map((f) => f.name).join('/');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final folder = _current;
    setState(() {
      _children = null;
      _error = null;
    });
    try {
      final children = await _remote.listFolders(folder.id);
      if (mounted && folder == _current) setState(() => _children = children);
    } catch (e) {
      if (mounted && folder == _current) setState(() => _error = e);
    }
  }

  void _open(RemoteFolder folder) {
    _stack.add(folder);
    _load();
  }

  void _goTo(int index) {
    if (index == _stack.length - 1) return;
    _stack.removeRange(index + 1, _stack.length);
    _load();
  }

  Future<void> _createFolder() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NewFolderDialog(initialName: widget.suggestedName),
    );
    if (name == null || name.isEmpty) return;
    try {
      final folder = await _remote.createFolder(
        parentId: _current.id,
        name: name,
      );
      if (mounted) _open(folder);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo crear la carpeta: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stack.length == 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goTo(_stack.length - 2);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_current.name),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(40),
            child: _Breadcrumbs(stack: _stack, onTap: _goTo),
          ),
          actions: [
            IconButton(
              tooltip: 'Nueva carpeta',
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: _createFolder,
            ),
          ],
        ),
        body: _buildBody(),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: () => Navigator.of(
                context,
              ).pop(DriveFolderSelection(id: _current.id, path: _currentPath)),
              icon: const Icon(Icons.check),
              label: Text('Sincronizar con «${_current.name}»'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No se pudo cargar la carpeta:\n$_error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }
    final children = _children;
    if (children == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (children.isEmpty) {
      return const Center(child: Text('Esta carpeta no tiene subcarpetas'));
    }
    return ListView.builder(
      itemCount: children.length,
      itemBuilder: (context, index) {
        final folder = children[index];
        return ListTile(
          leading: const Icon(Icons.folder),
          title: Text(folder.name),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(folder),
        );
      },
    );
  }
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.stack, required this.onTap});

  final List<RemoteFolder> stack;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: stack.length,
        separatorBuilder: (_, _) => const Icon(Icons.chevron_right, size: 18),
        itemBuilder: (context, reversedIndex) {
          final index = stack.length - 1 - reversedIndex;
          return TextButton(
            onPressed: () => onTap(index),
            child: Text(stack[index].name),
          );
        },
      ),
    );
  }
}

class _NewFolderDialog extends StatefulWidget {
  const _NewFolderDialog({this.initialName});

  final String? initialName;

  @override
  State<_NewFolderDialog> createState() => _NewFolderDialogState();
}

class _NewFolderDialogState extends State<_NewFolderDialog> {
  late final _controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva carpeta'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Nombre'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Crear')),
      ],
    );
  }
}
