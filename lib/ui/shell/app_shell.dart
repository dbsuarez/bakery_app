import 'package:flutter/material.dart';

import '../batches/batches_list_screen.dart';
import '../customers/customers_list_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../remittance/remittance_screen.dart';
import '../settings/settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _destinations = [
    NavigationDestination(icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
    NavigationDestination(icon: Icon(Icons.inventory_2_outlined),
        selectedIcon: Icon(Icons.inventory_2), label: 'Batches'),
    NavigationDestination(icon: Icon(Icons.people_outline),
        selectedIcon: Icon(Icons.people), label: 'Customers'),
    NavigationDestination(icon: Icon(Icons.receipt_long_outlined),
        selectedIcon: Icon(Icons.receipt_long), label: 'Remittance'),
    NavigationDestination(icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings), label: 'Settings'),
  ];

  static const _screens = [
    DashboardScreen(),
    BatchesListScreen(initialFilter: BatchFilter.awaiting),
    CustomersListScreen(),
    RemittanceScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 700;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: _destinations
                  .map((d) => NavigationRailDestination(
                        icon: d.icon,
                        selectedIcon: d.selectedIcon,
                        label: Text(d.label),
                      ))
                  .toList(),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _screens[_index]),
          ],
        ),
      );
    }

    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: _destinations,
      ),
    );
  }
}
