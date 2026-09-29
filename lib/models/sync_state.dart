/// Estado de un archivo tal y como quedó tras la última sincronización
/// correcta. Comparándolo con el estado actual se detecta qué lado cambió.
class FileSyncState {
  const FileSyncState({
    required this.localModifiedMs,
    required this.localSize,
    required this.remoteId,
    required this.remoteMd5,
    required this.remoteModifiedMs,
  });

  final int localModifiedMs;
  final int localSize;
  final String remoteId;
  final String? remoteMd5;
  final int remoteModifiedMs;

  Map<String, dynamic> toJson() => {
    'lm': localModifiedMs,
    'ls': localSize,
    'ri': remoteId,
    'rh': remoteMd5,
    'rm': remoteModifiedMs,
  };

  factory FileSyncState.fromJson(Map<String, dynamic> json) => FileSyncState(
    localModifiedMs: json['lm'] as int,
    localSize: json['ls'] as int,
    remoteId: json['ri'] as String,
    remoteMd5: json['rh'] as String?,
    remoteModifiedMs: json['rm'] as int,
  );
}
