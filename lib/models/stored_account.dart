/// Datos mínimos de la cuenta de Google con la que se inició sesión. Se guardan
/// en disco para que la tarea en segundo plano sepa qué cuenta autorizar.
class StoredAccount {
  const StoredAccount({
    required this.id,
    required this.email,
    this.displayName,
    this.photoUrl,
  });

  final String id;
  final String email;
  final String? displayName;
  final String? photoUrl;

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'displayName': displayName,
    'photoUrl': photoUrl,
  };

  factory StoredAccount.fromJson(Map<String, dynamic> json) => StoredAccount(
    id: json['id'] as String,
    email: json['email'] as String,
    displayName: json['displayName'] as String?,
    photoUrl: json['photoUrl'] as String?,
  );
}
