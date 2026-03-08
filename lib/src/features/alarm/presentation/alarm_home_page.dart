import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../ui/widgets/settings_widgets.dart';

import '../application/alarm_attention_controller.dart';
import '../application/alarm_engine.dart';
import '../application/alarm_scheduler_sync.dart';
import '../data/alarm_settings_store.dart';
import '../data/in_memory_alarm_repository.dart';
import '../domain/alarm.dart';
import '../domain/alarm_occurrence.dart' as occurrence_utils;
import '../domain/alarm_tone.dart';
import '../../failsafe/application/fail_safe_controller.dart';
import '../../failsafe/presentation/fail_safe_tab.dart';
import '../../update/application/app_update_controller.dart';
import '../../verint_bridge/application/verint_schedule_bridge.dart';

class AlarmHomePage extends StatelessWidget {
  const AlarmHomePage({
    super.key,
    required this.repository,
    required this.alarmEngine,
    required this.settingsStore,
    required this.schedulerSync,
    required this.failSafeController,
    required this.appUpdateController,
    required this.verintBridge,
    required this.attentionController,
  });

  final InMemoryAlarmRepository repository;
  final AlarmEngine alarmEngine;
  final AlarmSettingsStore settingsStore;
  final AlarmSchedulerSync schedulerSync;
  final FailSafeController failSafeController;
  final AppUpdateController appUpdateController;
  final VerintScheduleBridge verintBridge;
  final AlarmAttentionController attentionController;

  @override
  Widget build(BuildContext context) {
    final listenable =
        Listenable.merge([repository, alarmEngine, settingsStore]);
    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) {
        final alarms = repository.getAll();
        final active = alarmEngine.activeAlarm;
        final settings = settingsStore.settings;
        final isCompactTabBar = MediaQuery.sizeOf(context).width < 720;
        final disableTabSwipe = MediaQuery.sizeOf(context).width >= 960;

        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(84),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: TabBar(
                      isScrollable: isCompactTabBar,
                      tabAlignment: isCompactTabBar
                          ? TabAlignment.start
                          : TabAlignment.fill,
                      indicator: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      indicatorPadding: const EdgeInsets.all(6),
                      labelPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 2,
                      ),
                      labelStyle:
                          Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                      splashBorderRadius: BorderRadius.circular(14),
                      tabs: const [
                        Tab(text: 'Alarms', icon: Icon(Icons.alarm_rounded)),
                        Tab(text: 'History', icon: Icon(Icons.history_rounded)),
                        Tab(text: 'Settings', icon: Icon(Icons.tune_rounded)),
                        Tab(
                            text: 'Fail-safe',
                            icon: Icon(Icons.shield_rounded)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            body: Stack(
              children: [
                TabBarView(
                  physics: disableTabSwipe
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  children: [
                    _CenteredTabContent(
                      child: _AlarmsTab(
                        alarms: alarms,
                        repository: repository,
                        alarmEngine: alarmEngine,
                        use24HourFormat: settings.use24HourFormat,
                      ),
                    ),
                    _CenteredTabContent(
                      child: _HistoryTab(
                        history: alarmEngine.history,
                        onClear: alarmEngine.clearHistory,
                      ),
                    ),
                    _CenteredTabContent(
                      child: _SettingsTab(
                        settingsStore: settingsStore,
                        schedulerSync: schedulerSync,
                        appUpdateController: appUpdateController,
                        verintBridge: verintBridge,
                        attentionController: attentionController,
                      ),
                    ),
                    _CenteredTabContent(
                      child: FailSafeTab(controller: failSafeController),
                    ),
                  ],
                ),
                if (active != null)
                  _ActiveAlarmOverlay(
                    active: active,
                    onDismiss: alarmEngine.dismissActive,
                    onSnooze: alarmEngine.snoozeActive,
                    use24HourFormat: settings.use24HourFormat,
                    snoozeMinutes: active.snoozeMinutes,
                  ),
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () async {
                final draft = await showDialog<AlarmDraft>(
                  context: context,
                  builder: (_) => const AlarmEditorDialog(),
                );
                if (draft == null) {
                  return;
                }
                repository.create(draft);
              },
              icon: const Icon(Icons.add),
              label: const Text('New Alarm'),
            ),
          ),
        );
      },
    );
  }
}

class _AlarmsTab extends StatefulWidget {
  const _AlarmsTab({
    required this.alarms,
    required this.repository,
    required this.alarmEngine,
    required this.use24HourFormat,
  });

  final List<Alarm> alarms;
  final InMemoryAlarmRepository repository;
  final AlarmEngine alarmEngine;
  final bool use24HourFormat;

  @override
  State<_AlarmsTab> createState() => _AlarmsTabState();
}

class _AlarmsTabState extends State<_AlarmsTab> {
  final Set<String> _selectedAlarmIds = <String>{};
  bool _selectionMode = false;

  @override
  void didUpdateWidget(covariant _AlarmsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final alarmIds = widget.alarms.map((alarm) => alarm.id).toSet();
    _selectedAlarmIds.removeWhere((id) => !alarmIds.contains(id));
    if (_selectedAlarmIds.isEmpty && _selectionMode) {
      _selectionMode = false;
    }
  }

  void _setSelectionMode(bool enabled) {
    setState(() {
      _selectionMode = enabled;
      if (!enabled) {
        _selectedAlarmIds.clear();
      }
    });
  }

  void _toggleSelected(String alarmId) {
    setState(() {
      if (_selectedAlarmIds.contains(alarmId)) {
        _selectedAlarmIds.remove(alarmId);
      } else {
        _selectedAlarmIds.add(alarmId);
      }
      if (_selectedAlarmIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedAlarmIds.length == widget.alarms.length) {
        _selectedAlarmIds.clear();
      } else {
        _selectedAlarmIds
          ..clear()
          ..addAll(widget.alarms.map((alarm) => alarm.id));
      }
    });
  }

  void _disableSelected() {
    for (final alarm in widget.alarms) {
      if (_selectedAlarmIds.contains(alarm.id) && alarm.isEnabled) {
        widget.repository.update(alarm.copyWith(isEnabled: false));
      }
    }
    _setSelectionMode(false);
  }

  void _deleteSelected() {
    final ids = _selectedAlarmIds.toList(growable: false);
    for (final id in ids) {
      widget.repository.delete(id);
    }
    _setSelectionMode(false);
  }

  void _showEnabledCountdownNotification(Alarm alarm) {
    if (!mounted || !alarm.isEnabled) {
      return;
    }
    final nextForAlarm = occurrence_utils.computeNextOccurrence(
      alarm: alarm,
      from: DateTime.now(),
    );
    if (nextForAlarm == null) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Enabled "${alarm.label}" for '
          '${_formatDateTime(nextForAlarm, widget.use24HourFormat)} '
          '(${_formatTimeUntil(nextForAlarm)})',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final next = widget.alarmEngine.nextOccurrence;
    final upcoming = widget.alarmEngine.upcoming(limit: 5);
    final hasSelection = _selectedAlarmIds.isNotEmpty;
    final allSelected = widget.alarms.isNotEmpty &&
        _selectedAlarmIds.length == widget.alarms.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      children: [
        _NextAlarmCard(
          occurrence: next,
          use24HourFormat: widget.use24HourFormat,
        ),
        const SizedBox(height: 14),
        _UpcomingCard(
          values: upcoming,
          use24HourFormat: widget.use24HourFormat,
        ),
        const SizedBox(height: 14),
        if (widget.alarms.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!_selectionMode)
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _selectionMode = true;
                      });
                    },
                    icon: const Icon(Icons.checklist_rounded),
                    label: const Text('Select'),
                  ),
                if (_selectionMode) ...[
                  Text(
                    '${_selectedAlarmIds.length} selected',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  OutlinedButton(
                    onPressed: _toggleSelectAll,
                    child: Text(allSelected ? 'Unselect all' : 'Select all'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: hasSelection ? _disableSelected : null,
                    icon: const Icon(Icons.notifications_off_rounded),
                    label: const Text('Disable'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: hasSelection ? _deleteSelected : null,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Delete'),
                  ),
                  TextButton(
                    onPressed: () => _setSelectionMode(false),
                    child: const Text('Cancel'),
                  ),
                ],
              ],
            ),
          ),
        if (widget.alarms.isNotEmpty) const SizedBox(height: 12),
        if (widget.alarms.isEmpty)
          const _EmptyState()
        else
          ...widget.alarms.map(
            (alarm) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _AlarmCard(
                alarm: alarm,
                use24HourFormat: widget.use24HourFormat,
                selectionMode: _selectionMode,
                selected: _selectedAlarmIds.contains(alarm.id),
                onToggleSelected: () => _toggleSelected(alarm.id),
                onChanged: (isEnabled) {
                  final updated = alarm.copyWith(isEnabled: isEnabled);
                  widget.repository.update(updated);
                  _showEnabledCountdownNotification(updated);
                },
                onDelete: () {
                  widget.repository.delete(alarm.id);
                },
                onTestNow: () {
                  widget.alarmEngine.triggerNow(alarm.id);
                },
                onEdit: () async {
                  final edited = await showDialog<AlarmDraft>(
                    context: context,
                    builder: (_) => AlarmEditorDialog(
                      initial: AlarmDraft(
                        label: alarm.label,
                        hour: alarm.hour,
                        minute: alarm.minute,
                        daysOfWeek: alarm.daysOfWeek,
                        isEnabled: alarm.isEnabled,
                        ringOnce: alarm.ringOnce,
                        snoozeMinutes: alarm.snoozeMinutes,
                        scheduledAt: alarm.scheduledAt,
                      ),
                    ),
                  );
                  if (edited == null) {
                    return;
                  }
                  widget.repository.update(
                    alarm.copyWith(
                      label: edited.label,
                      hour: edited.hour,
                      minute: edited.minute,
                      daysOfWeek: edited.daysOfWeek,
                      isEnabled: edited.isEnabled,
                      ringOnce: edited.ringOnce,
                      clearSnoozeMinutes: edited.snoozeMinutes == null,
                      snoozeMinutes: edited.snoozeMinutes,
                      clearScheduledAt: edited.scheduledAt == null,
                      scheduledAt: edited.scheduledAt,
                    ),
                  );
                  final updatedAlarm = alarm.copyWith(
                    label: edited.label,
                    hour: edited.hour,
                    minute: edited.minute,
                    daysOfWeek: edited.daysOfWeek,
                    isEnabled: edited.isEnabled,
                    ringOnce: edited.ringOnce,
                    clearSnoozeMinutes: edited.snoozeMinutes == null,
                    snoozeMinutes: edited.snoozeMinutes,
                    clearScheduledAt: edited.scheduledAt == null,
                    scheduledAt: edited.scheduledAt,
                  );
                  _showEnabledCountdownNotification(updatedAlarm);
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({
    required this.history,
    required this.onClear,
  });

  final List<AlarmHistoryEntry> history;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Recent activity',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: history.isEmpty ? null : onClear,
                    child: const Text('Clear'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(),
              const SizedBox(height: 10),
              Expanded(
                child: SelectionArea(
                  child: history.isEmpty
                      ? Center(
                          child: Text(
                            'No alarm activity yet.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        )
                      : SingleChildScrollView(
                          child: SelectableText(
                            history
                                .map(
                                  (entry) =>
                                      '${DateFormat('MMM d, HH:mm:ss').format(entry.at)}  ${entry.message}',
                                )
                                .join('\n'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({
    required this.settingsStore,
    required this.schedulerSync,
    required this.appUpdateController,
    required this.verintBridge,
    required this.attentionController,
  });

  final AlarmSettingsStore settingsStore;
  final AlarmSchedulerSync schedulerSync;
  final AppUpdateController appUpdateController;
  final VerintScheduleBridge verintBridge;
  final AlarmAttentionController attentionController;

  @override
  Widget build(BuildContext context) {
    final settings = settingsStore.settings;
    final toneItems = <DropdownMenuItem<String>>[
      if (Platform.isAndroid)
        const DropdownMenuItem<String>(
          value: alarmToneSystemDefault,
          child: Text('System Default'),
        ),
      ...alarmToneOptions.map(
        (tone) => DropdownMenuItem<String>(
          value: tone.id,
          child: Text(tone.label),
        ),
      ),
    ];
    final selectedTone = normalizeAlarmToneId(settings.alarmToneId);
    final hasSelectedTone = toneItems.any((item) => item.value == selectedTone);
    final toneValue = hasSelectedTone ? selectedTone : alarmToneMarimba;
    final listenable = Listenable.merge([verintBridge, appUpdateController]);
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom + 96;
    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) => ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Alarm behavior',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 12),
                  DurationSettingRow(
                    label: 'Snooze',
                    value: settings.snoozeMinutes,
                    min: 1,
                    max: 20,
                    onChanged: (value) {
                      settingsStore.update(
                        settings.copyWith(snoozeMinutes: value),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  DurationSettingRow(
                    label: 'Auto-stop timeout',
                    value: settings.ringTimeoutMinutes,
                    min: 1,
                    max: 30,
                    onChanged: (value) {
                      settingsStore.update(
                        settings.copyWith(ringTimeoutMinutes: value),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: toneValue,
                    decoration: const InputDecoration(
                      labelText: 'Alarm tone',
                    ),
                    items: toneItems,
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      settingsStore.update(
                        settings.copyWith(alarmToneId: value),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  ToggleSettingTile(
                    value: settings.useDarkMode,
                    title: 'Use dark mode',
                    onChanged: (value) {
                      settingsStore.update(
                        settings.copyWith(useDarkMode: value),
                      );
                    },
                  ),
                  ToggleSettingTile(
                    value: settings.use24HourFormat,
                    title: 'Use 24-hour time format',
                    onChanged: (value) {
                      settingsStore.update(
                        settings.copyWith(use24HourFormat: value),
                      );
                    },
                  ),
                  if (Platform.isWindows) ...[
                    ToggleSettingTile(
                      value: settings.minimizeToTrayOnClose,
                      title: 'Minimize to tray when closing window',
                      onChanged: (value) {
                        settingsStore.update(
                          settings.copyWith(minimizeToTrayOnClose: value),
                        );
                      },
                    ),
                    ToggleSettingTile(
                      value: settings.showCloseBehaviorPrompt,
                      title: 'Ask what to do on close',
                      subtitle: 'Show close prompt with remember choice',
                      onChanged: (value) {
                        settingsStore.update(
                          settings.copyWith(showCloseBehaviorPrompt: value),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (Platform.isAndroid)
                    FilledButton.tonalIcon(
                      onPressed: schedulerSync.requestPermissions,
                      icon: const Icon(Icons.verified_user_outlined),
                      label: const Text('Request Android alarm permissions'),
                    )
                  else if (Platform.isWindows)
                    FilledButton.tonalIcon(
                      onPressed: schedulerSync.syncNow,
                      icon: const Icon(Icons.sync),
                      label: const Text('Re-sync Windows scheduled tasks'),
                    ),
                ],
              ),
            ),
          ),
          if (Platform.isWindows) ...[
            const SizedBox(height: 12),
            _WindowsOutputDeviceCard(
              settingsStore: settingsStore,
              attentionController: attentionController,
            ),
          ],
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'App updates',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  const Divider(),
                  const SizedBox(height: 10),
                  if (appUpdateController.latest != null) ...[
                    Text(
                      'Current: ${appUpdateController.latest!.currentVersion}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      'Latest: ${appUpdateController.latest!.latestVersion}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      appUpdateController.latest!.message,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ] else ...[
                    const Text(
                        'Check GitHub Releases to find new app versions.'),
                  ],
                  if (appUpdateController.error != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      appUpdateController.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: appUpdateController.isChecking
                            ? null
                            : appUpdateController.checkForUpdates,
                        icon: appUpdateController.isChecking
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.system_update_alt_rounded),
                        label: const Text('Check updates'),
                      ),
                      FilledButton.icon(
                        onPressed: _canOpenUpdate(appUpdateController)
                            ? () async {
                                final ok =
                                    await appUpdateController.openUpdateUrl();
                                if (!ok && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content:
                                          Text('Unable to open update URL.'),
                                    ),
                                  );
                                }
                              }
                            : null,
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Download update'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    Platform.isAndroid
                        ? 'Android installs require user confirmation.'
                        : 'Windows opens the latest installer/download.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          if (Platform.isWindows) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Verint Schedule Bridge',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    const Divider(),
                    const SizedBox(height: 10),
                    Text(
                      verintBridge.status,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    SelectableText(verintBridge.endpoint),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: verintBridge.isRunning
                              ? verintBridge.stop
                              : verintBridge.start,
                          icon: Icon(
                            verintBridge.isRunning
                                ? Icons.stop_circle
                                : Icons.play_arrow,
                          ),
                          label: Text(verintBridge.isRunning
                              ? 'Stop bridge'
                              : 'Start bridge'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(
                                text: _bookmarkletForEndpoint(
                                    verintBridge.endpoint),
                              ),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Bookmarklet copied to clipboard')),
                              );
                            }
                          },
                          icon: const Icon(Icons.copy),
                          label: const Text('Copy bookmarklet'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Run the bookmarklet on the Verint schedule page to send alarms into this app.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WindowsOutputDeviceCard extends StatefulWidget {
  const _WindowsOutputDeviceCard({
    required this.settingsStore,
    required this.attentionController,
  });

  final AlarmSettingsStore settingsStore;
  final AlarmAttentionController attentionController;

  @override
  State<_WindowsOutputDeviceCard> createState() =>
      _WindowsOutputDeviceCardState();
}

class _WindowsOutputDeviceCardState extends State<_WindowsOutputDeviceCard> {
  List<AlarmOutputDevice> _devices = const <AlarmOutputDevice>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshDevices();
  }

  Future<void> _refreshDevices() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final devices = await widget.attentionController.listOutputDevices();
      if (!mounted) {
        return;
      }
      setState(() {
        _devices = devices;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _devices = const <AlarmOutputDevice>[];
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settingsStore.settings;
    final selected = settings.alarmOutputDeviceId ?? 'auto';
    final available = _devices.isEmpty
        ? const <AlarmOutputDevice>[
            AlarmOutputDevice(id: 'auto', label: 'System default'),
          ]
        : _devices;
    final resolved = available.any((d) => d.id == selected) ? selected : 'auto';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Alarm speaker (Windows)',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            const Divider(),
            const SizedBox(height: 10),
            Text(
              'Pick which output device alarm audio should use.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_loading)
              const LinearProgressIndicator()
            else
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: resolved,
                decoration: const InputDecoration(
                  labelText: 'Output device',
                  border: OutlineInputBorder(),
                ),
                items: available
                    .map(
                      (device) => DropdownMenuItem<String>(
                        value: device.id,
                        child: Text(
                          device.description == null ||
                                  device.description!.trim().isEmpty
                              ? device.label
                              : '${device.label} (${device.description})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) async {
                  if (value == null) {
                    return;
                  }
                  final messenger = ScaffoldMessenger.of(context);
                  final normalized = value == 'auto' ? null : value;
                  widget.settingsStore.update(
                    settings.copyWith(
                      alarmOutputDeviceId: normalized,
                      clearAlarmOutputDeviceId: normalized == null,
                    ),
                  );
                  await widget.attentionController
                      .setPreferredOutputDevice(normalized);
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Alarm output device updated.'),
                    ),
                  );
                },
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _loading ? null : _refreshDevices,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh devices'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _canOpenUpdate(AppUpdateController controller) {
  if (controller.isLaunching || controller.isChecking) {
    return false;
  }
  final latest = controller.latest;
  if (latest == null) {
    return false;
  }
  if (!latest.isSupportedPlatform || !latest.hasUpdate) {
    return false;
  }
  return latest.downloadUrl.isNotEmpty || latest.releaseUrl.isNotEmpty;
}

String _bookmarkletForEndpoint(String endpoint) {
  const template = r'''javascript:(async()=>{
const uniq=new Map();
const add=(label,h,m,days,uniqueKey,scheduledAtMs,endSpec,durationMinutes)=>{
  h=Number(h);m=Number(m);
  if(!Number.isFinite(h)||!Number.isFinite(m)||h<0||h>23||m<0||m>59)return;
  const d=(Array.isArray(days)?days:[]).map(Number).filter(n=>n>=1&&n<=7);
  const safeLabel=((label||'Shift')+'').trim()||'Shift';
  const key=uniqueKey||((h+':'+m+':'+safeLabel));
  let normalizedEnd=null;
  if(endSpec&&typeof endSpec==='object'){
    const eh=Number(endSpec.hour),em=Number(endSpec.minute),ems=Number(endSpec.scheduledAtMs);
    if(Number.isFinite(eh)&&Number.isFinite(em)&&eh>=0&&eh<=23&&em>=0&&em<=59){
      normalizedEnd={hour:eh,minute:em,scheduled_at_ms:Number.isFinite(ems)?ems:null};
    }
  }
  if(!uniq.has(key)){
    uniq.set(key,{
      label:safeLabel,
      hour:h,
      minute:m,
      days_of_week:d,
      scheduled_at_ms:scheduledAtMs||null,
      end_hour:normalizedEnd?.hour??null,
      end_minute:normalizedEnd?.minute??null,
      end_scheduled_at_ms:normalizedEnd?.scheduled_at_ms??null,
      duration_minutes:Number.isFinite(Number(durationMinutes))?Number(durationMinutes):null,
      enabled:true
    });
  }
};
const toWeekday=(y,mo,da)=>{const wd=new Date(y,mo-1,da).getDay();return wd===0?7:wd;};
const parseDateTimes=(txt)=>{
  const values=[];const rx=/(\d{1,2})\/(\d{1,2})\/(\d{4})\s+(\d{1,2}):(\d{2})\s*(AM|PM)?/ig;
  let m;
  while((m=rx.exec(txt||''))!==null){
    let h=Number(m[4]);const min=Number(m[5]);const ampm=(m[6]||'').toUpperCase();
    if(ampm==='PM'&&h<12)h+=12;
    if(ampm==='AM'&&h===12)h=0;
    values.push({year:Number(m[3]),month:Number(m[1]),day:Number(m[2]),hour:h,minute:min});
  }
  return values;
};
const parseDurationMinutes=(txt)=>{
  const value=(txt||'').toLowerCase();
  if(!value)return null;
  const hm=[...value.matchAll(/\b(\d{1,2}):(\d{2})\b/g)];
  if(hm.length>0){
    const last=hm[hm.length-1];
    const h=Number(last[1]),m=Number(last[2]);
    if(Number.isFinite(h)&&Number.isFinite(m))return h*60+m;
  }
  const hAndM=value.match(/\b(\d+)\s*h(?:ours?)?\s*(\d+)?\s*m?(?:in(?:ute)?s?)?\b/);
  if(hAndM){
    const h=Number(hAndM[1]),m=Number(hAndM[2]||0);
    if(Number.isFinite(h)&&Number.isFinite(m))return h*60+m;
  }
  const mins=value.match(/\b(\d+)\s*m(?:in(?:ute)?s?)\b/);
  if(mins){
    const m=Number(mins[1]);
    if(Number.isFinite(m))return m;
  }
  return null;
};
const docs=[document];
document.querySelectorAll('iframe').forEach(f=>{try{if(f.contentDocument)docs.push(f.contentDocument);}catch(_){}}); 
const findCellBySuffix=(tr,suffix)=>[...tr.querySelectorAll('td')].find(td=>(td.id||'').endsWith(suffix));
const scrape=(doc)=>{
  const scheduleRows=[...doc.querySelectorAll('#oTableWrapper tbody tr.scheduleItem')];
  const parsedScheduleRows=scheduleRows.map((tr,idx)=>{
    const timeCell=findCellBySuffix(tr,'c0');
    const labelCell=findCellBySuffix(tr,'c2')||findCellBySuffix(tr,'c1');
    const durationCell=findCellBySuffix(tr,'c3');
    const rowText=(tr.innerText||tr.textContent||'');
    const durationText=(durationCell?.innerText||durationCell?.textContent||'').trim();
    const dts=parseDateTimes((timeCell?.innerText||timeCell?.textContent||''));
    if(dts.length===0)return null;
    const start=dts[0];
    const end=dts.length>1?dts[dts.length-1]:null;
    const wd=toWeekday(start.year,start.month,start.day);
    const sid=tr.getAttribute('scheduleid')||String(idx);
    const label=(labelCell?.innerText||labelCell?.textContent||'Shift').replace(/\s+/g,' ').trim();
    const scheduledAtMs=new Date(start.year,start.month-1,start.day,start.hour,start.minute,0,0).getTime();
    const endSpec=end?{
      hour:end.hour,
      minute:end.minute,
      scheduledAtMs:new Date(end.year,end.month-1,end.day,end.hour,end.minute,0,0).getTime()
    }:null;
    return {tr,rowText,durationText,start,wd,sid,label,scheduledAtMs,endSpec};
  }).filter(Boolean);
  const lastByDay=new Map();
  parsedScheduleRows.forEach((row)=>{
    const dayKey=row.start.year+'-'+row.start.month+'-'+row.start.day;
    const current=lastByDay.get(dayKey);
    if(!current||row.scheduledAtMs>current.scheduledAtMs){
      lastByDay.set(dayKey,row);
    }
  });
  parsedScheduleRows.forEach((row)=>{
    const dayKey=row.start.year+'-'+row.start.month+'-'+row.start.day;
    const isLast=lastByDay.get(dayKey)===row;
    const durationMinutes=isLast?parseDurationMinutes(row.durationText||row.rowText):null;
    add(row.label,row.start.hour,row.start.minute,[row.wd],('table:'+row.sid+':'+row.start.year+'-'+row.start.month+'-'+row.start.day),row.scheduledAtMs,row.endSpec,durationMinutes);
  });
  doc.querySelectorAll('[data-hour][data-minute]').forEach((el,idx)=>add(el.getAttribute('data-label')||el.textContent,el.getAttribute('data-hour'),el.getAttribute('data-minute'),(el.getAttribute('data-days')||'').split(','),('datahm:'+idx)));
  doc.querySelectorAll('[data-time]').forEach((el,idx)=>{const t=(el.getAttribute('data-time')||'').match(/(\d{1,2})[:.](\d{2})/);if(t)add(el.getAttribute('data-label')||el.textContent,t[1],t[2],[],('datatime:'+idx));});
  if(uniq.size===0){
    doc.querySelectorAll('td,th,tr,li,div,span').forEach((el,idx)=>{
      const txt=(el.innerText||el.textContent||'').trim();
      if(!txt)return;
      const dts=parseDateTimes(txt);
      if(dts.length>0){
        const dt=dts[0];
        const end=dts.length>1?dts[dts.length-1]:null;
        const label=txt.replace(/(\d{1,2})\/(\d{1,2})\/(\d{4})\s+(\d{1,2}):(\d{2})\s*(AM|PM)?/ig,'').replace(/\s+/g,' ').trim()||'Shift';
        const wd=toWeekday(dt.year,dt.month,dt.day);
        const scheduledAtMs=new Date(dt.year,dt.month-1,dt.day,dt.hour,dt.minute,0,0).getTime();
        const endSpec=end?{
          hour:end.hour,
          minute:end.minute,
          scheduledAtMs:new Date(end.year,end.month-1,end.day,end.hour,end.minute,0,0).getTime()
        }:null;
        const durationMinutes=parseDurationMinutes(txt);
        add(label,dt.hour,dt.minute,[wd],('dt:'+idx),scheduledAtMs,endSpec,durationMinutes);
        return;
      }
      const t=txt.match(/\b(\d{1,2})[:.](\d{2})\b/);
      if(!t)return;
      const label=txt.replace(t[0],'').replace(/\s+/g,' ').trim()||'Shift';
      add(label,t[1],t[2],[],('time:'+idx));
    });
  }
};
docs.forEach(scrape);
let rows=[...uniq.values()];
if(rows.length===0){
  const sample='[{"label":"Morning","hour":6,"minute":30,"days_of_week":[1,2,3,4,5],"enabled":true}]';
  const manual=prompt('No alarms auto-detected. Paste JSON array of alarms:',sample);
  if(!manual){alert('Import cancelled');return;}
  try{
    const parsed=JSON.parse(manual);
    if(Array.isArray(parsed)){rows=parsed;}
    else if(parsed&&Array.isArray(parsed.alarms)){rows=parsed.alarms;}
    else{throw new Error('Expected array');}
  }catch(e){alert('Invalid JSON: '+e);return;}
}
const res=await fetch('__VERINT_BRIDGE_ENDPOINT__',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({alarms:rows})});
let body='';try{body=await res.text();}catch(_){}
if(!res.ok){alert('Bridge error '+res.status+'\n'+body);return;}
alert('Sent '+rows.length+' alarms to NeverMiss Alarm');
})();''';
  return template.replaceFirst('__VERINT_BRIDGE_ENDPOINT__', endpoint);
}

class _NextAlarmCard extends StatelessWidget {
  const _NextAlarmCard({
    required this.occurrence,
    required this.use24HourFormat,
  });

  final AlarmOccurrence? occurrence;
  final bool use24HourFormat;

  @override
  Widget build(BuildContext context) {
    final label = occurrence == null
        ? 'No enabled alarms'
        : '${occurrence!.alarmLabel} - ${_formatDateTime(occurrence!.when, use24HourFormat)}';
    final relative =
        occurrence == null ? null : _formatTimeUntil(occurrence!.when);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const Icon(Icons.schedule_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Next alarm',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (relative != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      relative,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({
    required this.values,
    required this.use24HourFormat,
  });

  final List<AlarmOccurrence> values;
  final bool use24HourFormat;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Upcoming',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (values.isEmpty)
              Text(
                'No upcoming alarms',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              ...values.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${_formatDateTime(item.when, use24HourFormat)}  ${item.alarmLabel}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AlarmCard extends StatelessWidget {
  const _AlarmCard({
    required this.alarm,
    required this.use24HourFormat,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleSelected,
    required this.onChanged,
    required this.onDelete,
    required this.onEdit,
    required this.onTestNow,
  });

  final Alarm alarm;
  final bool use24HourFormat;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onToggleSelected;
  final ValueChanged<bool> onChanged;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onTestNow;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      color: selectionMode && selected
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                if (selectionMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Checkbox(
                      value: selected,
                      onChanged: (_) => onToggleSelected?.call(),
                    ),
                  ),
                Expanded(
                  child: Text(
                    _formatTime(alarm.hour, alarm.minute, use24HourFormat),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (!selectionMode)
                  Switch(
                    value: alarm.isEnabled,
                    onChanged: onChanged,
                  ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    alarm.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (!selectionMode) ...[
                  IconButton(
                    onPressed: onTestNow,
                    icon: const Icon(Icons.notifications_active_outlined),
                    tooltip: 'Test',
                  ),
                  IconButton(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit',
                  ),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete',
                  ),
                ],
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${alarm.scheduledAt != null ? DateFormat('yyyy-MM-dd').format(alarm.scheduledAt!) : alarm.daysLabel} | Snooze ${alarm.snoozeMinutes ?? 'Global'}${alarm.ringOnce ? ' | Ring once' : ''}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
    if (!selectionMode) {
      return card;
    }
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onToggleSelected,
      child: card,
    );
  }
}

class _ActiveAlarmOverlay extends StatelessWidget {
  const _ActiveAlarmOverlay({
    required this.active,
    required this.onDismiss,
    required this.onSnooze,
    required this.use24HourFormat,
    required this.snoozeMinutes,
  });

  final ActiveAlarmState active;
  final VoidCallback onDismiss;
  final VoidCallback onSnooze;
  final bool use24HourFormat;
  final int snoozeMinutes;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: const Color(0xEE1B263B),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.alarm_on_rounded,
                      size: 56,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      active.label,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Alarm is ringing',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Auto-stop at ${_formatDateTime(active.autoStopAt, use24HourFormat)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: onDismiss,
                            child: const Text('Dismiss'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: onSnooze,
                            child: Text('Snooze ${snoozeMinutes}m'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.alarm_off_rounded,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'No alarms yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text('Create your first alarm to get started.'),
          ],
        ),
      ),
    );
  }
}

class _CenteredTabContent extends StatelessWidget {
  const _CenteredTabContent({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1100) {
          return child;
        }
        final desktopWidth = constraints.maxWidth >= 1700 ? 1440.0 : 1280.0;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: desktopWidth,
            child: child,
          ),
        );
      },
    );
  }
}

class AlarmEditorDialog extends StatefulWidget {
  const AlarmEditorDialog({
    super.key,
    this.initial,
  });

  final AlarmDraft? initial;

  @override
  State<AlarmEditorDialog> createState() => _AlarmEditorDialogState();
}

class _AlarmEditorDialogState extends State<AlarmEditorDialog> {
  late final TextEditingController _labelController;
  late TimeOfDay _time;
  late bool _isEnabled;
  late _AlarmRepeatMode _repeatMode;
  late Set<int> _days;
  late bool _useGlobalSnooze;
  late double _snoozeMinutes;
  DateTime? _scheduledDate;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _labelController = TextEditingController(text: initial?.label ?? '');
    _time = TimeOfDay(hour: initial?.hour ?? 7, minute: initial?.minute ?? 0);
    _isEnabled = initial?.isEnabled ?? true;
    _repeatMode = (initial?.ringOnce ?? false)
        ? _AlarmRepeatMode.ringOnce
        : _AlarmRepeatMode.weekly;
    _days = {
      ...(initial?.daysOfWeek ?? {1, 2, 3, 4, 5})
    };
    _useGlobalSnooze = initial?.snoozeMinutes == null;
    _snoozeMinutes = (initial?.snoozeMinutes ?? 5).toDouble();
    _scheduledDate = initial?.scheduledAt;
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isCompactLayout = size.width < 640 || size.height < 720;
    if (isCompactLayout) {
      return Dialog.fullscreen(
        child: SafeArea(
          child: Column(
            children: [
              AppBar(
                title:
                    Text(widget.initial == null ? 'New alarm' : 'Edit alarm'),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _buildEditorForm(context),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saveAndClose,
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      title: Text(widget.initial == null ? 'New alarm' : 'Edit alarm'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: size.height * 0.68,
        ),
        child: SingleChildScrollView(
          child: _buildEditorForm(context),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saveAndClose,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildEditorForm(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _labelController,
          decoration: const InputDecoration(
            labelText: 'Label',
            hintText: 'Morning shift',
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await showDialog<TimeOfDay>(
              context: context,
              builder: (_) => _WheelTimePickerDialog(initialTime: _time),
            );
            if (picked != null) {
              setState(() {
                _time = picked;
              });
            }
          },
          icon: const Icon(Icons.schedule),
          label: Text('Time ${_time.format(context)}'),
        ),
        const SizedBox(height: 12),
        Text(
          'Repeat',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        SegmentedButton<_AlarmRepeatMode>(
          segments: const [
            ButtonSegment<_AlarmRepeatMode>(
              value: _AlarmRepeatMode.weekly,
              label: Text('Weekly'),
              icon: Icon(Icons.repeat),
            ),
            ButtonSegment<_AlarmRepeatMode>(
              value: _AlarmRepeatMode.ringOnce,
              label: Text('Ring once'),
              icon: Icon(Icons.looks_one_rounded),
            ),
          ],
          selected: {_repeatMode},
          onSelectionChanged: (selection) {
            final mode = selection.first;
            setState(() {
              _repeatMode = mode;
              if (mode == _AlarmRepeatMode.weekly) {
                _scheduledDate = null;
                if (_days.isEmpty) {
                  _days = {1, 2, 3, 4, 5};
                }
              } else {
                _days = <int>{};
              }
            });
          },
        ),
        const SizedBox(height: 8),
        if (_repeatMode == _AlarmRepeatMode.weekly)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(7, (index) {
              final day = index + 1;
              const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
              return FilterChip(
                label: Text(labels[index]),
                selected: _days.contains(day),
                onSelected: (value) {
                  setState(() {
                    if (value) {
                      _days.add(day);
                    } else if (_days.length > 1) {
                      _days.remove(day);
                    }
                  });
                },
              );
            }),
          ),
        if (_repeatMode == _AlarmRepeatMode.ringOnce) ...[
          OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                firstDate: DateTime(now.year - 1),
                lastDate: DateTime(now.year + 2),
                initialDate: _scheduledDate ?? now,
              );
              if (picked != null) {
                setState(() {
                  _scheduledDate = picked;
                });
              }
            },
            icon: const Icon(Icons.event),
            label: Text(
              _scheduledDate == null
                  ? 'Pick specific date (optional)'
                  : 'Date ${DateFormat('yyyy-MM-dd').format(_scheduledDate!)}',
            ),
          ),
          if (_scheduledDate != null)
            TextButton(
              onPressed: () {
                setState(() {
                  _scheduledDate = null;
                });
              },
              child: const Text('Clear date'),
            ),
        ],
        const SizedBox(height: 8),
        SwitchListTile(
          value: _isEnabled,
          contentPadding: EdgeInsets.zero,
          title: const Text('Enabled'),
          onChanged: (value) {
            setState(() {
              _isEnabled = value;
            });
          },
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          value: _useGlobalSnooze,
          contentPadding: EdgeInsets.zero,
          title: const Text('Use global snooze'),
          subtitle: const Text('Turn off to set custom snooze for this alarm'),
          onChanged: (value) {
            setState(() {
              _useGlobalSnooze = value;
            });
          },
        ),
        if (!_useGlobalSnooze) ...[
          Text('Snooze ${_snoozeMinutes.round()} min'),
          Slider(
            min: 1,
            max: 20,
            divisions: 19,
            label: '${_snoozeMinutes.round()} min',
            value: _snoozeMinutes,
            onChanged: (value) {
              setState(() {
                _snoozeMinutes = value;
              });
            },
          ),
        ],
      ],
    );
  }

  void _saveAndClose() {
    final label = _labelController.text.trim();
    final isRingOnce = _repeatMode == _AlarmRepeatMode.ringOnce;
    final days =
        isRingOnce ? <int>{} : (_days.isEmpty ? <int>{1, 2, 3, 4, 5} : _days);
    final scheduledAt = isRingOnce && _scheduledDate != null
        ? DateTime(
            _scheduledDate!.year,
            _scheduledDate!.month,
            _scheduledDate!.day,
            _time.hour,
            _time.minute,
          )
        : null;
    Navigator.of(context).pop(
      AlarmDraft(
        label: label.isEmpty ? 'Alarm' : label,
        hour: _time.hour,
        minute: _time.minute,
        daysOfWeek: days,
        isEnabled: _isEnabled,
        ringOnce: isRingOnce,
        snoozeMinutes: _useGlobalSnooze ? null : _snoozeMinutes.round(),
        scheduledAt: scheduledAt,
      ),
    );
  }
}

class _WheelTimePickerDialog extends StatefulWidget {
  const _WheelTimePickerDialog({
    required this.initialTime,
  });

  final TimeOfDay initialTime;

  @override
  State<_WheelTimePickerDialog> createState() => _WheelTimePickerDialogState();
}

class _WheelTimePickerDialogState extends State<_WheelTimePickerDialog> {
  static const _itemExtent = 40.0;
  bool _didInit = false;

  late final bool _use24HourFormat;
  late int _selectedMinute;
  late int _selectedHour24;
  late int _selectedHour12;
  late int _selectedPeriod;

  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;
  FixedExtentScrollController? _periodController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) {
      return;
    }
    _didInit = true;
    _use24HourFormat = MediaQuery.alwaysUse24HourFormatOf(context);
    _selectedHour24 = widget.initialTime.hour;
    _selectedMinute = widget.initialTime.minute;
    _selectedHour12 = widget.initialTime.hourOfPeriod == 0
        ? 12
        : widget.initialTime.hourOfPeriod;
    _selectedPeriod =
        widget.initialTime.period == DayPeriod.am ? 0 : 1; // 0: AM, 1: PM
    _hourController = FixedExtentScrollController(
      initialItem: _use24HourFormat ? _selectedHour24 : _selectedHour12 - 1,
    );
    _minuteController = FixedExtentScrollController(initialItem: _selectedMinute);
    if (!_use24HourFormat) {
      _periodController = FixedExtentScrollController(initialItem: _selectedPeriod);
    }
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _periodController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select time'),
      content: SizedBox(
        width: 340,
        height: 220,
        child: Row(
          children: [
            Expanded(
              child: _buildWheel(
                controller: _hourController,
                itemCount: _use24HourFormat ? 24 : 12,
                onSelectedItemChanged: (index) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    if (_use24HourFormat) {
                      _selectedHour24 = index;
                    } else {
                      _selectedHour12 = index + 1;
                    }
                  });
                },
                labelBuilder: (index) => _use24HourFormat
                    ? index.toString().padLeft(2, '0')
                    : (index + 1).toString().padLeft(2, '0'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text(':', style: TextStyle(fontSize: 24)),
            ),
            Expanded(
              child: _buildWheel(
                controller: _minuteController,
                itemCount: 60,
                onSelectedItemChanged: (index) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedMinute = index;
                  });
                },
                labelBuilder: (index) => index.toString().padLeft(2, '0'),
              ),
            ),
            if (!_use24HourFormat && _periodController != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _buildWheel(
                  controller: _periodController!,
                  itemCount: 2,
                  onSelectedItemChanged: (index) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedPeriod = index;
                    });
                  },
                  labelBuilder: (index) => index == 0 ? 'AM' : 'PM',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final hour = _use24HourFormat
                ? _selectedHour24
                : (_selectedHour12 % 12) + (_selectedPeriod == 1 ? 12 : 0);
            Navigator.of(context).pop(
              TimeOfDay(hour: hour, minute: _selectedMinute),
            );
          },
          child: const Text('Set'),
        ),
      ],
    );
  }

  Widget _buildWheel({
    required FixedExtentScrollController controller,
    required int itemCount,
    required ValueChanged<int> onSelectedItemChanged,
    required String Function(int index) labelBuilder,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: _itemExtent,
        diameterRatio: 1.3,
        perspective: 0.004,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: onSelectedItemChanged,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: itemCount,
          builder: (context, index) {
            return Center(
              child: Text(
                labelBuilder(index),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            );
          },
        ),
      ),
    );
  }
}

enum _AlarmRepeatMode {
  weekly,
  ringOnce,
}

String _formatTime(int hour, int minute, bool use24HourFormat) {
  final now = DateTime.now();
  final value = DateTime(now.year, now.month, now.day, hour, minute);
  return DateFormat(use24HourFormat ? 'HH:mm' : 'hh:mm a').format(value);
}

String _formatDateTime(DateTime value, bool use24HourFormat) {
  return DateFormat(
          use24HourFormat ? 'EEE, MMM d - HH:mm' : 'EEE, MMM d - hh:mm a')
      .format(value);
}

String _formatTimeUntil(DateTime target, {DateTime? from}) {
  final now = from ?? DateTime.now();
  var diff = target.difference(now);
  if (diff.isNegative) {
    diff = Duration.zero;
  }
  if (diff.inMinutes < 1) {
    return 'in less than a minute';
  }
  final days = diff.inDays;
  final hours = diff.inHours % 24;
  final minutes = diff.inMinutes % 60;
  final parts = <String>[];
  if (days > 0) {
    parts.add('$days day${days == 1 ? '' : 's'}');
  }
  if (hours > 0) {
    parts.add('$hours hour${hours == 1 ? '' : 's'}');
  }
  if (minutes > 0 && days == 0) {
    parts.add('$minutes min');
  }
  return 'in ${parts.join(' ')}';
}
