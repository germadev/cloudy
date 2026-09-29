import 'package:flutter/material.dart';

import '../models/folder_pair.dart';
import '../models/sync_report.dart';
import 'formatting.dart';

enum _MenuAction { edit, toggle, delete }

class PairCard extends StatelessWidget {
  const PairCard({
    super.key,
    required this.pair,
    required this.progress,
    required this.pending,
    required this.onTap,
    required this.onSync,
    required this.onToggleEnabled,
    required this.onDelete,
  });

  final FolderPair pair;
  final SyncProgress? progress;
  final bool pending;
  final VoidCallback onTap;
  final VoidCallback onSync;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onDelete;

  bool get _busy => progress != null || pending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: pair.enabled
                        ? colors.primaryContainer
                        : colors.surfaceContainerHighest,
                    foregroundColor: pair.enabled
                        ? colors.onPrimaryContainer
                        : colors.outline,
                    child: Icon(modeIcon(pair.mode)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pair.name,
                          style: theme.textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          modeLabel(pair.mode) +
                              (pair.enabled ? '' : ' · automática en pausa'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sincronizar ahora',
                    onPressed: _busy ? null : onSync,
                    icon: const Icon(Icons.sync),
                  ),
                  PopupMenuButton<_MenuAction>(
                    onSelected: (action) => switch (action) {
                      _MenuAction.edit => onTap(),
                      _MenuAction.toggle => onToggleEnabled(!pair.enabled),
                      _MenuAction.delete => onDelete(),
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: _MenuAction.edit,
                        child: Text('Editar'),
                      ),
                      PopupMenuItem(
                        value: _MenuAction.toggle,
                        child: Text(
                          pair.enabled
                              ? 'Pausar sincronización automática'
                              : 'Reanudar sincronización automática',
                        ),
                      ),
                      const PopupMenuItem(
                        value: _MenuAction.delete,
                        child: Text('Dejar de sincronizar'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _PathRow(icon: Icons.phone_android, text: pair.localPath),
              const SizedBox(height: 4),
              _PathRow(icon: Icons.add_to_drive, text: pair.remoteFolderPath),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _StatusLine(
                  pair: pair,
                  progress: progress,
                  pending: pending,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PathRow extends StatelessWidget {
  const _PathRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.pair,
    required this.progress,
    required this.pending,
  });

  final FolderPair pair;
  final SyncProgress? progress;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final progress = this.progress;

    if (progress != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: progress.fraction),
          const SizedBox(height: 6),
          Text(
            progress.describe(),
            style: theme.textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }
    if (pending) {
      return Text('En espera…', style: theme.textTheme.bodySmall);
    }

    final lastSync = pair.lastSyncAt;
    if (lastSync == null) {
      return Text(
        'Todavía no se ha sincronizado',
        style: theme.textTheme.bodySmall?.copyWith(color: colors.outline),
      );
    }

    final (icon, color) = switch (pair.lastOutcome) {
      SyncOutcome.success => (Icons.check_circle, Colors.green),
      SyncOutcome.partial => (Icons.warning_amber_rounded, Colors.orange),
      SyncOutcome.cancelled => (Icons.pause_circle_outline, colors.outline),
      SyncOutcome.failed || null => (Icons.error_outline, colors.error),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${relativeTime(lastSync)} · ${pair.lastMessage ?? ''}',
            style: theme.textTheme.bodySmall,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
