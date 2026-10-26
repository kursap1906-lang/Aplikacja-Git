import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/providers.dart';
import 'login_page.dart';

typedef AuthenticatedWorkspaceBuilder = Widget Function(
  BuildContext context,
  Map<String, dynamic> session,
  Future<void> Function() logout,
);

/// Validates the server session before mounting any user-specific workspace.
class AuthenticatedWorkspaceGate extends ConsumerStatefulWidget {
  const AuthenticatedWorkspaceGate({required this.builder, super.key});

  final AuthenticatedWorkspaceBuilder builder;

  @override
  ConsumerState<AuthenticatedWorkspaceGate> createState() =>
      _AuthenticatedWorkspaceGateState();
}

class _AuthenticatedWorkspaceGateState
    extends ConsumerState<AuthenticatedWorkspaceGate> {
  Map<String, dynamic>? _session;
  String? _error;
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _session = null;
      _error = null;
    });
    final api = ref.read(apiClientProvider);
    try {
      final session = await api.loadSession();
      if (!mounted || generation != _generation) return;
      setState(() => _session = session);
    } on ApiException catch (error) {
      if (!mounted || generation != _generation) return;
      if (error.code == 'UNAUTHENTICATED') {
        try {
          await api.forgetSession();
        } on Exception catch (storageError) {
          if (!mounted || generation != _generation) return;
          setState(
            () => _error =
                'Nie udało się wyczyścić wygasłej sesji: $storageError',
          );
        }
      } else {
        setState(() => _error = error.toString());
      }
    } on Exception catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = 'Nie udało się sprawdzić sesji: $error');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _logout() async {
    await ref.read(apiClientProvider).signOut();
    if (!mounted) return;
    ++_generation;
    setState(() {
      _session = null;
      _error = null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 36),
                const SizedBox(height: 16),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Sprawdź sesję ponownie'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final session = _session;
    if (session == null) return LoginPage(onAuthenticated: _reload);
    return _WorkspaceProviderScope(
      key: ValueKey(_generation),
      api: ref.read(apiClientProvider),
      session: session,
      child: Builder(
        builder: (context) => widget.builder(context, session, _logout),
      ),
    );
  }
}

class _WorkspaceProviderScope extends StatefulWidget {
  const _WorkspaceProviderScope({
    required this.api,
    required this.session,
    required this.child,
    super.key,
  });

  final ApiClient api;
  final Map<String, dynamic> session;
  final Widget child;

  @override
  State<_WorkspaceProviderScope> createState() =>
      _WorkspaceProviderScopeState();
}

class _WorkspaceProviderScopeState extends State<_WorkspaceProviderScope> {
  late final ProviderContainer _container;

  @override
  void initState() {
    super.initState();
    // A parentless container also isolates providers without declared dependencies.
    _container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(widget.api),
        sessionProvider.overrideWith((ref) async => true),
        sessionDataProvider.overrideWith((ref) async => widget.session),
      ],
    );
  }

  @override
  void dispose() {
    _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      UncontrolledProviderScope(container: _container, child: widget.child);
}
