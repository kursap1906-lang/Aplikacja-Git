import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme.dart';

typedef NavigationDestination = ({String path, String label, IconData icon});

const appNavigationDestinations = <NavigationDestination>[
  (path: '/dashboard', label: 'Pulpit', icon: Icons.space_dashboard_outlined),
  (path: '/teams', label: 'Zespoły AI', icon: Icons.groups_outlined),
  (path: '/bots', label: 'Boty i role', icon: Icons.smart_toy_outlined),
  (path: '/accounts', label: 'Konta GitHub', icon: Icons.account_circle_outlined),
  (path: '/repositories', label: 'Repozytoria', icon: Icons.source_outlined),
  (path: '/projects', label: 'Projekty i PDF', icon: Icons.folder_open_outlined),
  (path: '/tasks', label: 'Zadania i etapy', icon: Icons.task_alt_outlined),
  (path: '/collaboration', label: 'Współpraca', icon: Icons.forum_outlined),
  (path: '/pull-requests', label: 'Pull Requesty', icon: Icons.merge_type_outlined),
  (path: '/code-center', label: 'Code Center', icon: Icons.code_rounded),
  (path: '/review', label: 'Review Center', icon: Icons.fact_check_outlined),
  (path: '/schedule', label: 'Harmonogram pracy', icon: Icons.calendar_month_outlined),
  (path: '/costs', label: 'Koszty AI', icon: Icons.payments_outlined),
  (path: '/notifications', label: 'Powiadomienia', icon: Icons.notifications_none_rounded),
  (path: '/settings', label: 'Ustawienia', icon: Icons.settings_outlined),
];

class AppShell extends StatelessWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  NavigationDestination destinationFor(String route) {
    if (route.contains('/pull-requests/')) {
      return appNavigationDestinations[8];
    }
    if (route.startsWith('/bots/')) {
      return appNavigationDestinations[2];
    }
    return appNavigationDestinations.firstWhere(
      (item) => route == item.path || route.startsWith('${item.path}/'),
      orElse: () => appNavigationDestinations.first,
    );
  }

  void navigate(BuildContext context, String path) {
    Navigator.of(context).pop();
    context.go(path);
  }

  @override
  Widget build(BuildContext context) {
    final route = GoRouterState.of(context).uri.path;
    final selected = destinationFor(route);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Scaffold(
            appBar: AppBar(
              title: Text(selected.label),
              leading: Builder(
                builder: (context) => IconButton(
                  tooltip: 'Otwórz nawigację',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.menu_rounded),
                ),
              ),
              actions: [
                IconButton(
                  tooltip: 'Powiadomienia',
                  onPressed: () => context.go('/notifications'),
                  icon: const Icon(Icons.notifications_none_rounded),
                ),
              ],
            ),
            drawer: Drawer(
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Brand(),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        children: [
                          for (final item in appNavigationDestinations)
                            _DestinationButton(
                              item: item,
                              selected: item.path == selected.path,
                              onPressed: () => navigate(context, item.path),
                            ),
                        ],
                      ),
                    ),
                    const _NavigationFootnote(),
                  ],
                ),
              ),
            ),
            body: child,
          );
        }

        return Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: constraints.maxWidth < 1020 ? 226 : 252,
                child: ColoredBox(
                  color: AppColors.panel,
                  child: SafeArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _Brand(),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            children: [
                              for (final item in appNavigationDestinations)
                                _DestinationButton(
                                  item: item,
                                  selected: item.path == selected.path,
                                  onPressed: () => context.go(item.path),
                                ),
                            ],
                          ),
                        ),
                        const _NavigationFootnote(),
                      ],
                    ),
                  ),
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(
                child: Column(
                  children: [
                    _ContextBar(
                      label: selected.label,
                      onNotifications: () => context.go('/notifications'),
                      onSettings: () => context.go('/settings'),
                    ),
                    Expanded(child: child),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 16, 20),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.hub_rounded, color: AppColors.blue, size: 19),
            ),
            const SizedBox(width: 11),
            const Expanded(
              child: Text(
                'Copilot\nControl Center',
                style: TextStyle(fontWeight: FontWeight.w700, height: 1.2),
              ),
            ),
          ],
        ),
      );
}

class _ContextBar extends StatelessWidget {
  const _ContextBar({
    required this.label,
    required this.onNotifications,
    required this.onSettings,
  });

  final String label;
  final VoidCallback onNotifications;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => Container(
        height: 62,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.stroke)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 12),
            const Text(
              '·  Bez wybranego projektu',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Powiadomienia',
              onPressed: onNotifications,
              icon: const Icon(Icons.notifications_none_rounded),
            ),
            IconButton(
              tooltip: 'Ustawienia',
              onPressed: onSettings,
              icon: const Icon(Icons.account_circle_outlined),
            ),
          ],
        ),
      );
}

class _DestinationButton extends StatelessWidget {
  const _DestinationButton({
    required this.item,
    required this.selected,
    required this.onPressed,
  });

  final NavigationDestination item;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: selected ? AppColors.panelRaised : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    item.icon,
                    size: 19,
                    color: selected ? AppColors.blue : AppColors.muted,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        color: selected ? AppColors.foreground : AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _NavigationFootnote extends StatelessWidget {
  const _NavigationFootnote();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.fromLTRB(18, 10, 18, 16),
        child: Text(
          'Etap można zatwierdzić dopiero po weryfikacji CI, preview i testów.',
          style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.5),
        ),
      );
}
