import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/stored_account.dart';
import '../sync/remote_drive.dart';
import 'app_storage.dart';
import 'google_auth.dart';
import 'google_drive_remote.dart';

enum AuthStatus {
  initializing,
  signedOut,

  /// Sesión iniciada pero sin permiso para acceder a Drive.
  needsAuthorization,
  ready,
}

/// Estado de la sesión de Google para la interfaz.
class AuthService extends ChangeNotifier {
  AuthService(this._storage);

  final AppStorage _storage;

  AuthStatus _status = AuthStatus.initializing;
  GoogleSignInAccount? _user;
  String? _error;
  bool _busy = false;

  AuthStatus get status => _status;
  GoogleSignInAccount? get user => _user;
  String? get error => _error;
  bool get busy => _busy;

  Future<void> init() async {
    try {
      await initializeGoogleSignIn();
      final user = await GoogleSignIn.instance
          .attemptLightweightAuthentication();
      if (user == null) {
        _setStatus(AuthStatus.signedOut);
      } else {
        await _handleUser(user, promptForScopes: false);
      }
    } catch (e) {
      _error = _describe(e);
      _setStatus(AuthStatus.signedOut);
    }
  }

  /// Inicio de sesión interactivo. Debe llamarse desde un gesto del usuario.
  Future<void> signIn() async {
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      _error = 'Esta plataforma no admite el inicio de sesión con Google.';
      notifyListeners();
      return;
    }
    await _guard(() async {
      final user = await GoogleSignIn.instance.authenticate(
        scopeHint: GoogleAuthConfig.scopes,
      );
      await _handleUser(user, promptForScopes: true);
    });
  }

  /// Solicita el permiso de Drive si el usuario no lo concedió al entrar.
  Future<void> authorizeDrive() async {
    final user = _user;
    if (user == null) return;
    await _guard(() async {
      await user.authorizationClient.authorizeScopes(GoogleAuthConfig.scopes);
      _setStatus(AuthStatus.ready);
    });
  }

  Future<void> signOut() async {
    await _guard(() async {
      await GoogleSignIn.instance.disconnect();
      await _storage.clearAccount();
      _user = null;
      _setStatus(AuthStatus.signedOut);
    });
  }

  /// Acceso a Drive con la cuenta actual.
  RemoteDrive createRemote() {
    final user = _user;
    return GoogleDriveRemote(
      createDriveHttpClient(userId: user?.id, email: user?.email),
    );
  }

  Future<void> _handleUser(
    GoogleSignInAccount user, {
    required bool promptForScopes,
  }) async {
    _user = user;
    await _storage.saveAccount(
      StoredAccount(
        id: user.id,
        email: user.email,
        displayName: user.displayName,
        photoUrl: user.photoUrl,
      ),
    );
    _error = null;
    final authorization = await user.authorizationClient.authorizationForScopes(
      GoogleAuthConfig.scopes,
    );
    if (authorization != null) {
      _setStatus(AuthStatus.ready);
      return;
    }
    // Si el usuario cancela la petición de permisos, se queda en este estado
    // y la pantalla de acceso ofrece volver a pedirlos.
    _setStatus(AuthStatus.needsAuthorization);
    if (promptForScopes) {
      await user.authorizationClient.authorizeScopes(GoogleAuthConfig.scopes);
      _setStatus(AuthStatus.ready);
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) _error = _describe(e);
    } catch (e) {
      _error = _describe(e);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _setStatus(AuthStatus status) {
    _status = status;
    notifyListeners();
  }

  String _describe(Object error) {
    if (error is GoogleSignInException) {
      switch (error.code) {
        case GoogleSignInExceptionCode.clientConfigurationError:
        case GoogleSignInExceptionCode.providerConfigurationError:
          return 'La app no está bien configurada para Google Sign-In '
              '(${error.description ?? error.code.name}). Revisa el README.';
        case GoogleSignInExceptionCode.uiUnavailable:
          return 'No se pudo mostrar la ventana de inicio de sesión.';
        default:
          return error.description ?? error.code.name;
      }
    }
    return error.toString();
  }
}
