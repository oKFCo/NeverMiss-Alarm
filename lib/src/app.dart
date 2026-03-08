import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'features/alarm/application/alarm_attention_controller.dart';
import 'features/alarm/application/alarm_engine.dart';
import 'features/alarm/application/alarm_scheduler_sync.dart';
import 'features/alarm/data/alarm_settings_store.dart';
import 'features/alarm/data/in_memory_alarm_repository.dart';
import 'features/alarm/domain/alarm.dart';
import 'features/alarm/domain/alarm_scheduler.dart';
import 'features/alarm/presentation/alarm_home_page.dart';
import 'features/failsafe/application/fail_safe_controller.dart';
import 'features/update/application/app_update_controller.dart';
import 'features/update/application/app_update_service.dart';
import 'features/verint_bridge/application/verint_schedule_bridge.dart';
import 'core/ui/desktop_scroll_behavior.dart';
import 'theme/app_theme.dart';

class NeverMissAlarmApp extends StatefulWidget {
  const NeverMissAlarmApp({
    super.key,
    required this.repository,
    required this.settingsStore,
    required this.scheduler,
    required this.attentionController,
    required this.failSafeController,
    this.launchTriggerAlarmId,
  });

  final InMemoryAlarmRepository repository;
  final AlarmSettingsStore settingsStore;
  final AlarmScheduler scheduler;
  final AlarmAttentionController attentionController;
  final FailSafeController failSafeController;
  final String? launchTriggerAlarmId;

  @override
  State<NeverMissAlarmApp> createState() => _NeverMissAlarmAppState();
}

class _NeverMissAlarmAppState extends State<NeverMissAlarmApp>
    with WindowListener, TrayListener {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final InMemoryAlarmRepository _alarmRepository;
  late final AlarmSettingsStore _settingsStore;
  late final AlarmScheduler _scheduler;
  late final AlarmEngine _alarmEngine;
  late final AlarmSchedulerSync _schedulerSync;
  late final AlarmAttentionController _attentionController;
  late final FailSafeController _failSafeController;
  late final AppUpdateController _appUpdateController;
  late final VerintScheduleBridge _verintBridge;
  bool _isQuitting = false;
  bool _trayEnabled = false;

  @override
  void initState() {
    super.initState();
    _alarmRepository = widget.repository;
    if (kDebugMode) {
      _alarmRepository.seedDefaults(
        [
          AlarmDraft(
            label: 'Wake up',
            hour: 6,
            minute: 30,
            daysOfWeek: {1, 2, 3, 4, 5},
            isEnabled: true,
            ringOnce: false,
          ),
          AlarmDraft(
            label: 'Break reminder',
            hour: 14,
            minute: 0,
            daysOfWeek: {1, 2, 3, 4, 5},
            isEnabled: false,
            ringOnce: false,
          ),
        ],
      );
    }
    _settingsStore = widget.settingsStore;
    _scheduler = widget.scheduler;
    _attentionController = widget.attentionController;
    _failSafeController = widget.failSafeController;
    _alarmEngine = AlarmEngine(
      repository: _alarmRepository,
      settingsStore: _settingsStore,
      attentionController: _attentionController,
      onAlarmTimeoutAutoStop: _failSafeController.handleAlarmTimeout,
    )..start();
    _failSafeController
        .setIncomingAlertHandler((sourceName, alarmLabel, reason) async {
      await _alarmEngine.triggerIncomingFailSafeAlert(
        sourceName: sourceName,
        alarmLabel: alarmLabel,
        reason: reason,
      );
    });
    _schedulerSync = AlarmSchedulerSync(
      repository: _alarmRepository,
      scheduler: _scheduler,
    )..start();
    _appUpdateController = AppUpdateController(
      service: const AppUpdateService(
        githubOwner: 'oKFCo',
        githubRepo: 'NeverMiss-Alarm',
      ),
    );
    _verintBridge = VerintScheduleBridge(repository: _alarmRepository);
    if (Platform.isWindows) {
      _verintBridge.start();
      unawaited(_configureWindowsTrayBehavior());
    }
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _schedulerSync.requestPermissions();
      });
    }

    final launchTriggerAlarmId = widget.launchTriggerAlarmId;
    if (launchTriggerAlarmId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _alarmEngine.triggerFromPlatformSchedule(launchTriggerAlarmId);
      });
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      windowManager.removeListener(this);
      if (_trayEnabled) {
        trayManager.removeListener(this);
      }
      if (!_isQuitting && _trayEnabled) {
        unawaited(trayManager.destroy());
      }
    }
    _schedulerSync.dispose();
    _alarmEngine.dispose();
    _failSafeController.dispose();
    _appUpdateController.dispose();
    _verintBridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settingsStore,
      builder: (context, _) {
        final useDarkMode = _settingsStore.settings.useDarkMode;
        return MaterialApp(
          navigatorKey: _navigatorKey,
          title: 'NeverMiss Alarm',
          debugShowCheckedModeBanner: false,
          scrollBehavior: const DesktopScrollBehavior(),
          theme: buildAppTheme(),
          darkTheme: buildDarkAppTheme(),
          themeMode: useDarkMode ? ThemeMode.dark : ThemeMode.light,
          home: AlarmHomePage(
            repository: _alarmRepository,
            alarmEngine: _alarmEngine,
            settingsStore: _settingsStore,
            schedulerSync: _schedulerSync,
            failSafeController: _failSafeController,
            appUpdateController: _appUpdateController,
            verintBridge: _verintBridge,
            attentionController: _attentionController,
          ),
        );
      },
    );
  }

  Future<void> _configureWindowsTrayBehavior() async {
    try {
      windowManager.addListener(this);
      trayManager.addListener(this);
      await trayManager.setIcon(_trayIconPath());
      await trayManager.setToolTip('NeverMiss Alarm');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(
              key: 'show_window',
              label: 'Show NeverMiss Alarm',
            ),
            MenuItem.separator(),
            MenuItem(
              key: 'exit_app',
              label: 'Exit',
            ),
          ],
        ),
      );
      _trayEnabled = true;
      await windowManager.setPreventClose(true);
    } on MissingPluginException catch (error) {
      _trayEnabled = false;
      await windowManager.setPreventClose(false);
      debugPrint('Tray plugin unavailable on current run: $error');
    } catch (error) {
      _trayEnabled = false;
      await windowManager.setPreventClose(false);
      debugPrint('Failed to initialize tray behavior: $error');
    }
  }

  String _trayIconPath() {
    final sep = Platform.pathSeparator;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return '$exeDir${sep}data${sep}flutter_assets${sep}assets${sep}icons${sep}tray_icon.ico';
  }

  @override
  void onTrayIconMouseDown() {
    if (!_trayEnabled) {
      return;
    }
    unawaited(_showMainWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    if (!_trayEnabled) {
      return;
    }
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_window':
        unawaited(_showMainWindow());
        return;
      case 'exit_app':
        unawaited(_quitApplication());
        return;
      default:
        return;
    }
  }

  Future<void> _showMainWindow() async {
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  @override
  void onWindowClose() {
    unawaited(_handleCloseRequest());
  }

  Future<void> _handleCloseRequest() async {
    if (!Platform.isWindows || _isQuitting) {
      return;
    }
    if (!_trayEnabled) {
      await _quitApplication();
      return;
    }
    final preventClose = await windowManager.isPreventClose();
    if (!preventClose) {
      return;
    }

    final settings = _settingsStore.settings;
    var minimizeToTray = settings.minimizeToTrayOnClose;

    if (settings.showCloseBehaviorPrompt) {
      final decision = await _showCloseBehaviorDialog();
      if (!mounted || decision == null) {
        return;
      }
      minimizeToTray = decision.minimizeToTray;
      if (decision.neverShowAgain) {
        _settingsStore.update(
          settings.copyWith(
            minimizeToTrayOnClose: decision.minimizeToTray,
            showCloseBehaviorPrompt: false,
          ),
        );
      }
    }

    if (minimizeToTray) {
      await windowManager.hide();
      return;
    }
    await _quitApplication();
  }

  Future<void> _quitApplication() async {
    if (_isQuitting) {
      return;
    }
    _isQuitting = true;
    await windowManager.setPreventClose(false);
    if (_trayEnabled) {
      await trayManager.destroy();
    }
    await windowManager.close();
  }

  Future<_CloseBehaviorDecision?> _showCloseBehaviorDialog() async {
    final dialogContext = _navigatorKey.currentContext;
    if (dialogContext == null) {
      return null;
    }
    var neverShowAgain = false;
    return showDialog<_CloseBehaviorDecision>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('When closing NeverMiss Alarm'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose what should happen when you click the window close button.',
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: neverShowAgain,
                  title: const Text('Never show this again'),
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (value) {
                    setState(() {
                      neverShowAgain = value ?? false;
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('Cancel'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(
                  _CloseBehaviorDecision(
                    minimizeToTray: false,
                    neverShowAgain: neverShowAgain,
                  ),
                ),
                child: const Text('Exit app'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  _CloseBehaviorDecision(
                    minimizeToTray: true,
                    neverShowAgain: neverShowAgain,
                  ),
                ),
                child: const Text('Minimize to tray'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CloseBehaviorDecision {
  const _CloseBehaviorDecision({
    required this.minimizeToTray,
    required this.neverShowAgain,
  });

  final bool minimizeToTray;
  final bool neverShowAgain;
}
