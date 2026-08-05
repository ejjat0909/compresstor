// AppShell — sidebar + header + page stack, mirroring MainWindow (Qt).

import 'package:flutter/material.dart';

import '../components/button.dart';
import '../components/toast.dart';
import '../engine/update_applier.dart';
import '../engine/update_applier_macos.dart';
import '../engine/update_applier_windows.dart';
import '../engine/update_client.dart';
import '../pages/dashboard_page.dart';
import '../pages/history_page.dart';
import '../pages/settings_page.dart';
import '../state/update_controller.dart';
import '../theme/app_theme.dart';
import 'sidebar.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  String _current = 'dashboard';
  late final UpdateController _updateController;
  bool _scrollToUpdate = false;

  static const _titles = {
    'dashboard': 'Dashboard',
    'history': 'History',
    'settings': 'Settings',
  };

  @override
  void initState() {
    super.initState();
    final isWindows = UpdateClient.defaultUpdatePlatform() == 'windows';
    final UpdateApplier applier =
        isWindows ? WindowsUpdateApplier() : MacOsUpdateApplier();
    _updateController = UpdateController(
      client: UpdateClient(),
      applier: applier,
    );
    _updateController.addListener(_onUpdateChanged);
    _updateController.loadVersion().then((_) {
      _updateController.checkForUpdates();
    });
  }

  @override
  void dispose() {
    _updateController.removeListener(_onUpdateChanged);
    _updateController.dispose();
    super.dispose();
  }

  void _onUpdateChanged() {
    setState(() {});
  }

  void _goToUpdateSettings() {
    setState(() {
      _current = 'settings';
      _scrollToUpdate = true;
    });
  }

  Widget _pageFor(String id) {
    switch (id) {
      case 'history':
        return const HistoryPage();
      case 'settings':
        return SettingsPage(
          updateController: _updateController,
          scrollToUpdate: _scrollToUpdate,
          onScrollHandled: () {
            _scrollToUpdate = false;
          },
        );
      default:
        return const DashboardPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final palette = theme.palette;
    final hasUpdate =
        _updateController.status == UpdateStatus.updateAvailable;
    return ToastHost(
      child: Scaffold(
        backgroundColor: palette.bg,
        body: Row(
          children: [
            AppSidebar(
              items: AppSidebar.defaultItems,
              current: _current,
              onSelected: (id) => setState(() => _current = id),
              updateAvailable: hasUpdate,
              updateVersion: _updateController.manifest?.version.toString(),
              onUpdateTap: _goToUpdateSettings,
            ),
            Expanded(
              child: Column(
                children: [
                  _Header(title: _titles[_current] ?? _current),
                  Expanded(child: _pageFor(_current)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final palette = theme.palette;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: BoxDecoration(
        color: palette.header,
        border: Border(bottom: BorderSide(color: palette.borderSoft)),
      ),
      child: Row(
        children: [
          Text(title, style: theme.typography.sectionTitle),
          const Spacer(),
          AppButton(
            label: '',
            icon: 'info',
            variant: ButtonVariant.ghost,
            size: ButtonSize.icon,
            onPressed: () => ToastHost.of(context).info(
              'Compresstor',
              'Local file compression — files never leave this machine.',
            ),
          ),
        ],
      ),
    );
  }
}
