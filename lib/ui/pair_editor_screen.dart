import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../controllers/sync_controller.dart';
import '../models/folder_pair.dart';
import '../sync/path_filter.dart';
import 'drive_folder_picker.dart';
import 'formatting.dart';

/// Crea o edita un emparejamiento. Devuelve el [FolderPair] resultante.
class PairEditorScreen extends StatefulWidget {
  const PairEditorScreen({super.key, this.initial});

  final FolderPair? initial;

  @override
  State<PairEditorScreen> createState() => _PairEditorScreenState();
}

class _PairEditorScreenState extends State<PairEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _excludes = TextEditingController(
    text: widget.initial?.excludePatterns.join(', ') ?? '',
  );

  late String? _localPath = widget.initial?.localPath;
  late String? _remoteId = widget.initial?.remoteFolderId;
  late String? _remotePath = widget.initial?.remoteFolderPath;
  late SyncMode _mode = widget.initial?.mode ?? SyncMode.twoWay;
  late ConflictPolicy _conflictPolicy =
      widget.initial?.conflictPolicy ?? ConflictPolicy.keepBoth;
  late bool _propagateDeletions = widget.initial?.propagateDeletions ?? true;
  late bool _includeHidden = widget.initial?.includeHidden ?? false;
  late bool _enabled = widget.initial?.enabled ?? true;
  bool _showErrors = false;

  bool get _isNew => widget.initial == null;

  @override
  void dispose() {
    _name.dispose();
    _excludes.dispose();
    super.dispose();
  }

  Future<void> _pickLocal() async {
    final controller = context.read<SyncController>();
    if (!controller.hasStorageAccess &&
        !await controller.requestStorageAccess()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sin acceso a los archivos no se pueden sincronizar carpetas.',
          ),
        ),
      );
      return;
    }
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Carpeta a sincronizar',
    );
    if (path == null) return;
    setState(() {
      _localPath = path;
      if (_name.text.trim().isEmpty) _name.text = p.basename(path);
    });
  }

  Future<void> _pickRemote() async {
    final suggested = _localPath == null ? null : p.basename(_localPath!);
    final selection = await Navigator.of(context).push<DriveFolderSelection>(
      MaterialPageRoute(
        builder: (_) => DriveFolderPickerScreen(suggestedName: suggested),
      ),
    );
    if (selection == null) return;
    setState(() {
      _remoteId = selection.id;
      _remotePath = selection.path;
    });
  }

  String? _validateLocal(List<FolderPair> pairs) {
    final path = _localPath;
    if (path == null) return 'Elige una carpeta del dispositivo';
    final others = pairs.where((pair) => pair.id != widget.initial?.id);
    for (final other in others) {
      if (p.equals(other.localPath, path) ||
          p.isWithin(other.localPath, path) ||
          p.isWithin(path, other.localPath)) {
        return 'Se solapa con «${other.name}» (${other.localPath})';
      }
    }
    return null;
  }

  void _save() {
    setState(() => _showErrors = true);
    final formValid = _formKey.currentState!.validate();
    final pairs = context.read<SyncController>().pairs;
    if (!formValid || _validateLocal(pairs) != null || _remoteId == null) {
      return;
    }

    final base =
        widget.initial ??
        FolderPair(
          id: FolderPair.newId(),
          name: '',
          localPath: '',
          remoteFolderId: '',
          remoteFolderPath: '',
        );
    Navigator.of(context).pop(
      base.copyWith(
        name: _name.text.trim(),
        localPath: _localPath,
        remoteFolderId: _remoteId,
        remoteFolderPath: _remotePath,
        mode: _mode,
        conflictPolicy: _conflictPolicy,
        propagateDeletions: _propagateDeletions,
        includeHidden: _includeHidden,
        excludePatterns: PathFilter.parsePatterns(_excludes.text),
        enabled: _enabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pairs = context.watch<SyncController>().pairs;
    final localError = _showErrors ? _validateLocal(pairs) : null;
    final remoteError = _showErrors && _remoteId == null
        ? 'Elige una carpeta de Google Drive'
        : null;
    final mappingChanged =
        !_isNew &&
        (widget.initial!.localPath != _localPath ||
            widget.initial!.remoteFolderId != _remoteId);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Nueva sincronización' : 'Editar sincronización'),
        actions: [TextButton(onPressed: _save, child: const Text('Guardar'))],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _FolderField(
              icon: Icons.phone_android,
              label: 'Carpeta del dispositivo',
              value: _localPath,
              error: localError,
              onTap: _pickLocal,
            ),
            const SizedBox(height: 12),
            _FolderField(
              icon: Icons.add_to_drive,
              label: 'Carpeta de Google Drive',
              value: _remotePath,
              error: remoteError,
              onTap: _pickRemote,
            ),
            if (mappingChanged)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Al cambiar las carpetas, la próxima sincronización '
                  'comparará ambos lados desde cero. No se borrará nada; los '
                  'archivos que difieran se resolverán como conflictos.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.tertiary,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Ponle un nombre'
                  : null,
            ),
            const SizedBox(height: 24),
            Text('Dirección', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<SyncMode>(
              segments: [
                for (final mode in SyncMode.values)
                  ButtonSegment(
                    value: mode,
                    icon: Icon(modeIcon(mode)),
                    label: Text(modeLabel(mode)),
                  ),
              ],
              selected: {_mode},
              onSelectionChanged: (value) =>
                  setState(() => _mode = value.first),
            ),
            const SizedBox(height: 8),
            Text(modeDescription(_mode), style: theme.textTheme.bodySmall),
            if (_mode == SyncMode.twoWay) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<ConflictPolicy>(
                initialValue: _conflictPolicy,
                decoration: const InputDecoration(
                  labelText: 'Si un archivo cambia en ambos lados',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final policy in ConflictPolicy.values)
                    DropdownMenuItem(
                      value: policy,
                      child: Text(conflictLabel(policy)),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _conflictPolicy = value ?? _conflictPolicy),
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Propagar eliminaciones'),
              subtitle: Text(_deletionHelp()),
              value: _propagateDeletions,
              onChanged: (value) => setState(() => _propagateDeletions = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Incluir archivos ocultos'),
              subtitle: const Text('Archivos y carpetas que empiezan por «.»'),
              value: _includeHidden,
              onChanged: (value) => setState(() => _includeHidden = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Sincronización automática'),
              subtitle: const Text(
                'Incluir esta carpeta en la sincronización periódica',
              ),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _excludes,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Excluir',
                hintText: '*.tmp, cache, Thumbs.db',
                helperText:
                    'Patrones separados por comas. * y ? como comodines.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _deletionHelp() {
    if (!_propagateDeletions) {
      return 'Nunca se borra nada: lo eliminado en un lado se conserva en el '
          'otro.';
    }
    return switch (_mode) {
      SyncMode.twoWay =>
        'Lo que borres en un lado se borrará en el otro (en Drive va a la '
            'papelera).',
      SyncMode.uploadOnly =>
        'Lo que borres en el dispositivo irá a la papelera de Drive.',
      SyncMode.downloadOnly =>
        'Lo que se borre en Drive se borrará del dispositivo.',
    };
  }
}

class _FolderField extends StatelessWidget {
  const _FolderField({
    required this.icon,
    required this.label,
    required this.value,
    required this.error,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String? value;
  final String? error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: const Icon(Icons.chevron_right),
          errorText: error,
          border: const OutlineInputBorder(),
        ),
        isEmpty: value == null,
        child: Text(value ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
