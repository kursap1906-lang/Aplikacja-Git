import 'package:flutter/material.dart';
import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
import 'src/app_router.dart';
import 'src/core/api.dart';
import 'src/core/providers.dart';
import 'src/features/auth/login_page.dart';
import 'src/theme.dart';

final appRouter = createAppRouter();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient();

  runApp(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api)],
    child: const CopilotControlCenterApp(),
  ));
}

class CopilotControlCenterApp extends ConsumerStatefulWidget {
  const CopilotControlCenterApp({super.key});

  @override
  ConsumerState<CopilotControlCenterApp> createState() => _CopilotControlCenterAppState();
}

class _CopilotControlCenterAppState extends ConsumerState<CopilotControlCenterApp> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _deepLinkSubscription;
  String? _signInError;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;

    _appLinks = AppLinks();
    _deepLinkSubscription = _appLinks.uriLinkStream.listen(_handleDeepLink);
    unawaited(_handleInitialLink());
  }

  Future<void> _handleInitialLink() async {
    final uri = await _appLinks.getInitialLink();
    if (uri != null) await _handleDeepLink(uri);
  }

  Future<void> _handleDeepLink(Uri uri) async {
    if (uri.scheme != 'copilotcontrol' || uri.host != 'oauth' || uri.path != '/callback') return;
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    if (code == null || code.isEmpty || state == null || state.isEmpty) return;

    try {
      await ref.read(apiClientProvider).exchangeOAuthHandoff(code, state);
      ref.invalidate(sessionProvider);
      ref.invalidate(sessionDataProvider);
      ref.invalidate(botsProvider);
      setState(() => _signInError = null);
      appRouter.go('/dashboard');
    } on Object catch (error) {
      setState(() => _signInError = error.toString());
      appRouter.go('/login');
    }
  }

  @override
  void dispose() {
    _deepLinkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    return session.when(
      data: (authenticated) => authenticated || (kIsWeb && Uri.base.path == '/auth/complete')
          ? MaterialApp.router(
              title: 'Copilot Control Center',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.dark,
              locale: const Locale('pl', 'PL'),
              supportedLocales: const [Locale('pl', 'PL')],
              routerConfig: appRouter,
            )
          : MaterialApp(
              title: 'Copilot Control Center',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.dark,
              locale: const Locale('pl', 'PL'),
              home: LoginPage(error: _signInError),
            ),
      loading: () => MaterialApp(
        title: 'Copilot Control Center',
        theme: AppTheme.dark,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      error: (error, stack) => MaterialApp(
        title: 'Copilot Control Center',
        theme: AppTheme.dark,
        home: LoginPage(error: error.toString()),
      ),
    );
  }
}
