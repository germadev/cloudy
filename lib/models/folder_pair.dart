/// Dirección en la que se propagan los cambios entre el dispositivo y Drive.
enum SyncMode {
  /// Los cambios de ambos lados se replican en el otro.
  twoWay,

  /// Solo se suben cambios locales a Drive (copia de seguridad).
  uploadOnly,

  /// Solo se descargan a local los cambios de Drive.
  downloadOnly;

  bool get uploads => this != SyncMode.downloadOnly;
  bool get downloads => this != SyncMode.uploadOnly;
}

/// Qué hacer cuando un archivo ha cambiado en ambos lados desde la última
/// sincronización (solo aplica en modo bidireccional).
enum ConflictPolicy {
  /// Conserva las dos versiones: la local se renombra como copia en conflicto.
  keepBoth,

  /// Gana la versión del dispositivo.
  preferLocal,

  /// Gana la versión de Drive.
  preferRemote,

  /// Gana la versión modificada más recientemente.
  preferNewest,
}

enum SyncOutcome { success, partial, failed, cancelled }

/// Emparejamiento entre una carpeta local y una carpeta de Google Drive.
class FolderPair {
  const FolderPair({
    required this.id,
    required this.name,
    required this.localPath,
    required this.remoteFolderId,
    required this.remoteFolderPath,
    this.mode = SyncMode.twoWay,
    this.conflictPolicy = ConflictPolicy.keepBoth,
    this.propagateDeletions = true,
    this.includeHidden = false,
    this.excludePatterns = const [],
    this.enabled = true,
    this.lastSyncAt,
    this.lastOutcome,
    this.lastMessage,
  });

  final String id;
  final String name;
  final String localPath;
  final String remoteFolderId;

  /// Ruta legible de la carpeta en Drive, solo para mostrarla.
  final String remoteFolderPath;
  final SyncMode mode;
  final ConflictPolicy conflictPolicy;
  final bool propagateDeletions;
  final bool includeHidden;
  final List<String> excludePatterns;

  /// Si participa en la sincronización automática.
  final bool enabled;

  final DateTime? lastSyncAt;
  final SyncOutcome? lastOutcome;
  final String? lastMessage;

  static String newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  FolderPair copyWith({
    String? name,
    String? localPath,
    String? remoteFolderId,
    String? remoteFolderPath,
    SyncMode? mode,
    ConflictPolicy? conflictPolicy,
    bool? propagateDeletions,
    bool? includeHidden,
    List<String>? excludePatterns,
    bool? enabled,
    DateTime? lastSyncAt,
    SyncOutcome? lastOutcome,
    String? lastMessage,
  }) {
    return FolderPair(
      id: id,
      name: name ?? this.name,
      localPath: localPath ?? this.localPath,
      remoteFolderId: remoteFolderId ?? this.remoteFolderId,
      remoteFolderPath: remoteFolderPath ?? this.remoteFolderPath,
      mode: mode ?? this.mode,
      conflictPolicy: conflictPolicy ?? this.conflictPolicy,
      propagateDeletions: propagateDeletions ?? this.propagateDeletions,
      includeHidden: includeHidden ?? this.includeHidden,
      excludePatterns: excludePatterns ?? this.excludePatterns,
      enabled: enabled ?? this.enabled,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastOutcome: lastOutcome ?? this.lastOutcome,
      lastMessage: lastMessage ?? this.lastMessage,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'localPath': localPath,
    'remoteFolderId': remoteFolderId,
    'remoteFolderPath': remoteFolderPath,
    'mode': mode.name,
    'conflictPolicy': conflictPolicy.name,
    'propagateDeletions': propagateDeletions,
    'includeHidden': includeHidden,
    'excludePatterns': excludePatterns,
    'enabled': enabled,
    'lastSyncAt': lastSyncAt?.toIso8601String(),
    'lastOutcome': lastOutcome?.name,
    'lastMessage': lastMessage,
  };

  factory FolderPair.fromJson(Map<String, dynamic> json) {
    return FolderPair(
      id: json['id'] as String,
      name: json['name'] as String,
      localPath: json['localPath'] as String,
      remoteFolderId: json['remoteFolderId'] as String,
      remoteFolderPath: json['remoteFolderPath'] as String? ?? '',
      mode: _enumByName(SyncMode.values, json['mode'], SyncMode.twoWay),
      conflictPolicy: _enumByName(
        ConflictPolicy.values,
        json['conflictPolicy'],
        ConflictPolicy.keepBoth,
      ),
      propagateDeletions: json['propagateDeletions'] as bool? ?? true,
      includeHidden: json['includeHidden'] as bool? ?? false,
      excludePatterns:
          (json['excludePatterns'] as List<dynamic>?)?.cast<String>() ??
          const [],
      enabled: json['enabled'] as bool? ?? true,
      lastSyncAt: json['lastSyncAt'] == null
          ? null
          : DateTime.parse(json['lastSyncAt'] as String),
      lastOutcome: json['lastOutcome'] == null
          ? null
          : _enumByName(
              SyncOutcome.values,
              json['lastOutcome'],
              SyncOutcome.failed,
            ),
      lastMessage: json['lastMessage'] as String?,
    );
  }
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}
