import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme.dart';

const _destinations = [
  (path: '/dashboard', label: 'Przegląd', icon: Icons.space_dashboard_outlined),
  (path: '/accounts', label: 'Konta', icon: Icons.account_circle_outlined),
  (path: '/notifications', label: 'Powiadomienia', icon: Icons.notifications_none_rounded),
  (path: '/settings', label: 'Ustawienia', icon: Icons.settings_outlined),
];

class AppShell extends StatelessWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  int destinationFor(String route) {
    final index = _destinations.indexWhere((item) => route.startsWith(item.path));
    return index < 0 ? 0 : index;
  }

  void navigate(BuildContext context, int index) {
    context.go(_destinations[index].path);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final selected = destinationFor(GoRouterState.of(context).uri.path);
        if (constraints.maxWidth < 760) {
          return Scaffold(
            body: child,
            bottomNavigationBar: NavigationBar(
              height: 68,
              selectedIndex: selected,
              backgroundColor: AppColors.panel,
              onDestinationSelected: (index) => navigate(context, index),
              destinations: [
                for (final item in _destinations)
                  NavigationDestination(icon: Icon(item.icon), label: item.label),
              ],
            ),
          );
        }

        return Scaffold(
          body: Row(children: [
            SizedBox(
              width: constraints.maxWidth < 1020 ? 218 : 246,
              child: ColoredBox(
                color: AppColors.panel,
                child: SafeArea(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 26, 16, 38),
                      child: Row(children: [
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
                          child: Text('Copilot\nControl Center',
                              style: TextStyle(fontWeight: FontWeight.w700, height: 1.2)),
                        ),
                      ]),
                    ),
                    ...List.generate(_destinations.length, (index) {
                      final item = _destinations[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        child: NavigationDrawerDestinationButton(
                          item: item,
                          selected: selected == index,
                          onPressed: () => navigate(context, index),
                        ),
                      );
                    }),
                    const Spacer(),
                    const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('Etapy wymagają osobnej akceptacji. Pull requesty nie są scalane automatycznie.',
                          style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.5)),
                    ),
                  ]),
                ),
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: child),
          ]),
        );
      });
}

class NavigationDrawerDestinationButton extends StatelessWidget {
  const NavigationDrawerDestinationButton({
    required this.item,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final ({String path, String label, IconData icon}) item;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? AppColors.panelRaised : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(children: [
              Icon(item.icon, size: 19, color: selected ? AppColors.blue : AppColors.muted),
              const SizedBox(width: 12),
              Text(item.label, style: TextStyle(color: selected ? AppColors.foreground : AppColors.muted)),
            ]),
          ),
        ),
      );
}