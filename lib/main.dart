import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'auth/auth_gate.dart';
import 'celebration/celebration_controller.dart';
import 'celebration/celebration_overlay.dart';
import 'config.dart';
import 'customer_portal/customer_soa_portal_screen.dart';
import 'net/http_client.dart';
import 'repository/bakery_repository.dart';
import 'repository/remote_repository.dart';
import 'security/app_lock_service.dart';
import 'settings/business_settings_controller.dart';
import 'theme/theme_controller.dart';
import 'ui/splash/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
    httpClient: createPlatformHttpClient(),
  );
  runApp(const BakeryApp());
}

class BakeryApp extends StatelessWidget {
  const BakeryApp({super.key});

  @override
  Widget build(BuildContext context) {
    if (!SupabaseConfig.isConfigured) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: _MissingConfigScreen(),
      );
    }

    final soaToken = Uri.base.queryParameters['soa'];
    if (soaToken != null && soaToken.isNotEmpty) {
      return MaterialApp(
        title: 'Statement of Account',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B4513)),
          useMaterial3: true,
        ),
        home: CustomerSoaPortalScreen(token: soaToken),
      );
    }

    // Providers live above MaterialApp/Navigator (not inside `home`) so
    // that every pushed route - not just the initial one - can see them.
    return MultiProvider(
      providers: _providers(),
      child: Consumer<ThemeController>(
        builder: (context, themeController, _) => MaterialApp(
          title: 'My Bakery',
          debugShowCheckedModeBanner: false,
          theme: themeController.lightTheme,
          darkTheme: themeController.darkTheme,
          themeMode: themeController.mode,
          home: const CelebrationOverlay(
            child: AppStartupGate(child: AuthGate()),
          ),
        ),
      ),
    );
  }

  // Every platform talks to Supabase directly - no local database, no
  // background sync layer. App Lock stays mobile/desktop-only (a browser
  // tab can already be locked at the OS level).
  List<SingleChildWidget> _providers() {
    return [
      Provider<BakeryRepository>(
        create: (_) => RemoteRepository(Supabase.instance.client),
      ),
      Provider<AppLockService?>(
        create: (_) => kIsWeb ? null : AppLockService(),
      ),
      Provider<CelebrationController>(
        create: (_) => CelebrationController(),
        dispose: (_, c) => c.dispose(),
      ),
      ChangeNotifierProvider<ThemeController>(
        create: (_) => ThemeController()..load(),
      ),
      ChangeNotifierProvider<BusinessSettingsController>(
        create: (_) => BusinessSettingsController()..load(),
      ),
      ChangeNotifierProvider<AppState>(
        create: (context) => AppState(context.read<BakeryRepository>()),
      ),
    ];
  }
}

class _MissingConfigScreen extends StatelessWidget {
  const _MissingConfigScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Missing Supabase configuration.\n\n'
            'Run with:\n'
            'flutter run --dart-define-from-file=dart_define.json',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
