import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../security/app_lock_gate.dart';
import '../security/app_lock_service.dart';
import '../ui/shell/app_shell.dart';
import 'sign_in_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) {
          return const SignInScreen();
        }
        final lockService = context.watch<AppLockService?>();
        if (lockService != null) {
          return AppLockGate(lockService: lockService, child: const AppShell());
        }
        return const AppShell();
      },
    );
  }
}
