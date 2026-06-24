import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../shell/presentation/pages/app_shell_page.dart';
import '../../application/session_manager.dart';
import '../../domain/repositories/account_repository.dart';
import 'initial_setup_page.dart';
import 'login_page.dart';
import 'password_change_page.dart';

/// Routes to [InitialSetupPage], [LoginPage], or [AppShellPage] depending on
/// the current session state and whether the admin account needs initial setup.
///
/// Listens to [SessionManager.sessionStream]. When the stream emits
/// [AdminSessionExpired] the user is redirected to [LoginPage] without a
/// smooth transition — re-login is required before accessing any screen.
class AuthGatePage extends StatefulWidget {
  const AuthGatePage({super.key});

  @override
  State<AuthGatePage> createState() => _AuthGatePageState();
}

class _AuthGatePageState extends State<AuthGatePage> {
  late final SessionManager _sessionManager;
  late StreamSubscription<SessionState> _subscription;

  SessionState _sessionState = const Unauthenticated();
  bool _adminNeedsInitialSetup = false;
  bool _loadingAdminState = true;

  @override
  void initState() {
    super.initState();
    _sessionManager = getIt<SessionManager>();
    _sessionState = _sessionManager.currentState;
    _subscription = _sessionManager.sessionStream.listen(_onSessionChanged);
    _checkAdminSetup();
  }

  Future<void> _checkAdminSetup() async {
    try {
      final admin = await getIt<AccountRepository>().findById('admin');
      if (mounted) {
        setState(() {
          _adminNeedsInitialSetup = admin != null && admin.mustChangePassword;
          _loadingAdminState = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAdminState = false);
    }
  }

  void _onSessionChanged(SessionState state) {
    if (!mounted) return;
    setState(() {
      _sessionState = state;
      // When a new login occurs and admin no longer needs setup, clear the flag.
      if (state is Authenticated && !state.session.isRestrictedToPasswordChange) {
        _adminNeedsInitialSetup = false;
      }
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingAdminState) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final state = _sessionState;

    if (state is Unauthenticated || state is AdminSessionExpired) {
      if (_adminNeedsInitialSetup) {
        return InitialSetupPage(
          onSetupComplete: () {
            if (mounted) {
              setState(() => _adminNeedsInitialSetup = false);
            }
          },
        );
      }
      return const LoginPage();
    }

    if (state is Authenticated) {
      if (state.session.isRestrictedToPasswordChange) {
        return const PasswordChangePage();
      }
      return const AppShellPage();
    }

    return const LoginPage();
  }
}
