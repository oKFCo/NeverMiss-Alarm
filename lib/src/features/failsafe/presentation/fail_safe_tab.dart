import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../ui/widgets/status_indicator.dart';

import '../application/fail_safe_controller.dart';
import '../domain/fail_safe_models.dart';

enum _LogLevelFilter {
  all,
  info,
  warning,
  error,
}

class FailSafeTab extends StatelessWidget {
  const FailSafeTab({
    super.key,
    required this.controller,
  });

  final FailSafeController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final devices = controller.devices;
        final pairedDevices = devices.where((d) => d.isTrusted).toList();
        final discoveredDevices = devices.where((d) => !d.isTrusted).toList();
        final logs = controller.logs;
        final bottomPadding = MediaQuery.viewPaddingOf(context).bottom + 96;
        final overviewCard = Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Local Fail-safe',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                const Divider(),
                const SizedBox(height: 10),
                Text(
                  'This device: ${controller.localDeviceName}:${controller.listenPort}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  'Device ID: ${controller.localDeviceId}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: controller.localFailSafeEnabled,
                  title: const Text('Enable local fail-safe'),
                  subtitle: Text(
                    'Source: ${controller.localPlatform.name} | '
                    'controls timeout-trigger behavior (manual test still sends immediately).',
                  ),
                  onChanged: controller.setLocalFailSafeEnabled,
                ),
                if (Platform.isAndroid) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        avatar: Icon(
                          controller.androidKeepAliveEnabled
                              ? Icons.shield_rounded
                              : Icons.shield_outlined,
                          size: 16,
                        ),
                        label: Text(
                          controller.androidKeepAliveEnabled
                              ? 'Keep-alive active'
                              : 'Keep-alive inactive',
                        ),
                      ),
                      Chip(
                        avatar: Icon(
                          controller.androidIgnoringBatteryOptimizations
                              ? Icons.battery_saver
                              : Icons.battery_alert_rounded,
                          size: 16,
                        ),
                        label: Text(
                          controller.androidIgnoringBatteryOptimizations
                              ? 'Battery unrestricted'
                              : 'Battery optimized',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: controller.requestAndroidBatteryExemption,
                        icon: const Icon(Icons.battery_charging_full_rounded),
                        label: const Text('Allow unrestricted battery'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await controller.refreshAndroidPowerState();
                          await controller.refreshFailSafeDebugState();
                        },
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Refresh power status'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _AndroidRuntimeDebug(controller: controller),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: controller.discoverOnLan,
                      icon: const Icon(Icons.travel_explore_rounded),
                      label: const Text('Scan LAN'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _showAddDeviceDialog(context),
                      icon: const Icon(Icons.link_rounded),
                      label: const Text('Pair device'),
                    ),
                    TextButton.icon(
                      onPressed: controller.refreshDeviceStatus,
                      icon: const Icon(Icons.sync),
                      label: const Text('Refresh status'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Tip: If scan finds nothing, press Scan LAN on the other device too.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
        final devicesCard = Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Paired devices',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(),
                const SizedBox(height: 10),
                if (pairedDevices.isEmpty)
                  const Text('No paired devices yet.')
                else
                  ...pairedDevices.map(
                    (device) => _DeviceTile(
                      device: device,
                      onToggleEnabled: (value) =>
                          controller.toggleDeviceEnabled(device.id, value),
                      onRemove: () => controller.removeDevice(device.id),
                      isFailSafeTarget:
                          controller.isDeviceFailSafeTarget(device.id),
                      onToggleFailSafeTarget: (value) =>
                          controller.setDeviceFailSafeTarget(device.id, value),
                      onSendTest: () =>
                          controller.sendManualTestToDevice(device.id),
                      onSetSharedKey: (value) =>
                          controller.setDeviceSharedKey(device.id, value),
                    ),
                  ),
                if (discoveredDevices.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Discovered (not paired)',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  ...discoveredDevices.map(
                    (device) => _DeviceTile(
                      device: device,
                      onToggleEnabled: (value) =>
                          controller.toggleDeviceEnabled(device.id, value),
                      onRemove: () => controller.removeDevice(device.id),
                      isFailSafeTarget:
                          controller.isDeviceFailSafeTarget(device.id),
                      onToggleFailSafeTarget: null,
                      onSendTest: null,
                      onSetSharedKey: (value) =>
                          controller.setDeviceSharedKey(device.id, value),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
        final logsCard = Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompactHeader = constraints.maxWidth < 640;
                    final onCopyLogs = logs.isEmpty
                        ? null
                        : () async {
                            final text = logs.map((entry) {
                              final at = DateTime.fromMillisecondsSinceEpoch(
                                  entry.createdAtEpochMs);
                              return '${DateFormat('yyyy-MM-dd HH:mm:ss').format(at)} [${entry.level}] ${entry.message}';
                            }).join('\n');
                            await Clipboard.setData(
                              ClipboardData(text: text),
                            );
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Copied logs to clipboard'),
                              ),
                            );
                          };

                    if (isCompactHeader) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Fail-safe logs',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              if (logs.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '${logs.length}',
                                  style:
                                      Theme.of(context).textTheme.labelMedium,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed:
                                    logs.isEmpty ? null : controller.clearLogs,
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                ),
                                label: const Text('Clear logs'),
                              ),
                              OutlinedButton.icon(
                                onPressed: onCopyLogs,
                                icon: const Icon(
                                  Icons.content_copy_rounded,
                                  size: 18,
                                ),
                                label: const Text('Copy'),
                              ),
                            ],
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Text(
                          'Fail-safe logs',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Spacer(),
                        if (logs.isNotEmpty)
                          Text(
                            '${logs.length}',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: logs.isEmpty ? null : controller.clearLogs,
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 18),
                          label: const Text('Clear logs'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: onCopyLogs,
                          icon:
                              const Icon(Icons.content_copy_rounded, size: 18),
                          label: const Text('Copy'),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                const Divider(),
                const SizedBox(height: 10),
                _FailSafeLogPanel(logs: logs),
              ],
            ),
          ),
        );
        return LayoutBuilder(
          builder: (context, constraints) {
            final isDesktopLayout = constraints.maxWidth >= 960;
            if (!isDesktopLayout) {
              return ListView(
                padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
                children: [
                  overviewCard,
                  const SizedBox(height: 12),
                  devicesCard,
                  const SizedBox(height: 12),
                  logsCard,
                ],
              );
            }

            final contentWidth = constraints.maxWidth - 32;
            final cardWidth = (contentWidth - 12) / 2;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(width: cardWidth, child: overviewCard),
                  SizedBox(width: cardWidth, child: devicesCard),
                  SizedBox(width: cardWidth, child: logsCard),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAddDeviceDialog(BuildContext context) async {
    String deviceId = '';
    bool showDeviceIdError = false;
    String name = '';
    String address = '192.168.1.';
    String portText = '9851';
    String sharedKey = '';
    DevicePlatform platform = DevicePlatform.android;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Pair device'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      initialValue: deviceId,
                      onChanged: (value) {
                        deviceId = value;
                        if (showDeviceIdError && value.trim().isNotEmpty) {
                          setState(() => showDeviceIdError = false);
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'Device identifier',
                        hintText: 'e.g. android_1741165687340_12345',
                        errorText: showDeviceIdError
                            ? 'Device identifier is required'
                            : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: name,
                      onChanged: (value) => name = value,
                      decoration:
                          const InputDecoration(labelText: 'Device name'),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<DevicePlatform>(
                      initialValue: platform,
                      items: DevicePlatform.values
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => platform = value);
                        }
                      },
                      decoration: const InputDecoration(labelText: 'Platform'),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: address,
                      onChanged: (value) => address = value,
                      decoration:
                          const InputDecoration(labelText: 'IP address'),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: portText,
                      onChanged: (value) => portText = value,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Port'),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: sharedKey,
                      onChanged: (value) => sharedKey = value,
                      decoration: const InputDecoration(
                        labelText: 'Shared key (pairing secret)',
                      ),
                    ),
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
                    final safeDeviceId = deviceId.trim();
                    if (safeDeviceId.isEmpty) {
                      setState(() => showDeviceIdError = true);
                      return;
                    }
                    final safeName = name.trim();
                    final safeAddress = address.trim();
                    final port = int.tryParse(portText.trim()) ?? 9851;
                    controller.addDevice(
                      deviceId: safeDeviceId,
                      name: safeName.isEmpty ? 'Device' : safeName,
                      platform: platform,
                      address: safeAddress,
                      port: port,
                      sharedKeyHint: sharedKey.trim(),
                      isTrusted: sharedKey.trim().isNotEmpty,
                    );
                    Navigator.of(context).pop();
                  },
                  child: const Text('Pair'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _FailSafeLogPanel extends StatefulWidget {
  const _FailSafeLogPanel({
    required this.logs,
  });

  final List<FailSafeLogEntry> logs;

  @override
  State<_FailSafeLogPanel> createState() => _FailSafeLogPanelState();
}

class _FailSafeLogPanelState extends State<_FailSafeLogPanel> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _listController = ScrollController();
  _LogLevelFilter _filter = _LogLevelFilter.all;
  bool _autoScroll = true;

  @override
  void didUpdateWidget(covariant _FailSafeLogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_autoScroll && oldWidget.logs.length != widget.logs.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _listController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filteredLogs = widget.logs.where((entry) {
      if (!_matchesLevel(entry.level)) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      return entry.message.toLowerCase().contains(query) ||
          entry.level.toLowerCase().contains(query);
    }).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 520;
            final autoScrollToggle = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Auto-scroll'),
                Switch(
                  value: _autoScroll,
                  onChanged: (value) {
                    setState(() {
                      _autoScroll = value;
                    });
                    if (value) {
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => _scrollToBottom());
                    }
                  },
                ),
              ],
            );

            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search logs...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  autoScrollToggle,
                ],
              );
            }

            return Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search logs...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                autoScrollToggle,
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        ToggleButtons(
          isSelected: _LogLevelFilter.values.map((f) => f == _filter).toList(),
          onPressed: (index) {
            setState(() {
              _filter = _LogLevelFilter.values[index];
            });
          },
          children: const [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('All'),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('Info'),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('Warning'),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('Error'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (filteredLogs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No fail-safe events match the current filter.'),
          )
        else
          Container(
            constraints: const BoxConstraints(maxHeight: 300),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.35),
            ),
            child: Scrollbar(
              controller: _listController,
              thumbVisibility: true,
              child: ListView.builder(
                controller: _listController,
                itemCount: filteredLogs.length,
                itemBuilder: (context, index) {
                  final entry = filteredLogs[index];
                  final at = DateTime.fromMillisecondsSinceEpoch(
                    entry.createdAtEpochMs,
                  );
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 2,
                      horizontal: 4,
                    ),
                    child: SelectableText(
                      '${DateFormat('HH:mm:ss').format(at)} [${entry.level}] ${entry.message}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'Consolas',
                            height: 1.35,
                          ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  bool _matchesLevel(String level) {
    final normalized = level.toLowerCase();
    switch (_filter) {
      case _LogLevelFilter.all:
        return true;
      case _LogLevelFilter.info:
        return normalized.contains('info');
      case _LogLevelFilter.warning:
        return normalized.contains('warn');
      case _LogLevelFilter.error:
        return normalized.contains('error');
    }
  }

  void _scrollToBottom() {
    if (!_listController.hasClients) {
      return;
    }
    _listController.jumpTo(_listController.position.maxScrollExtent);
  }
}

class _AndroidRuntimeDebug extends StatelessWidget {
  const _AndroidRuntimeDebug({
    required this.controller,
  });

  final FailSafeController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.androidFailSafeDebugState;
    final owner = state['runtimeOwner'] as String? ?? 'unknown';
    final heartbeatAlive = state['heartbeatAlive'] as bool? ?? false;
    final heartbeatAgeMs = state['heartbeatAgeMs'];
    final heartbeatText =
        heartbeatAgeMs is num ? '${heartbeatAgeMs.toInt()} ms' : 'n/a';
    final backgroundEngineRunning =
        state['backgroundEngineRunning'] as bool? ?? false;
    final backgroundSocketsBound =
        state['backgroundSocketsBound'] as bool? ?? false;
    final uiSocketsBound = state['uiSocketsBound'] as bool? ?? false;
    final foregroundRunning = state['foregroundRunning'] as bool? ?? false;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Runtime debug',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: controller.refreshFailSafeDebugState,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
                'Foreground service: ${foregroundRunning ? "running" : "stopped"}'),
            Text(
                'Background engine: ${backgroundEngineRunning ? "running" : "stopped"}'),
            Text(
                'Heartbeat: ${heartbeatAlive ? "alive" : "stale"} ($heartbeatText)'),
            Text('Runtime owner: $owner'),
            Text('UI sockets bound: $uiSocketsBound'),
            Text('Background sockets bound: $backgroundSocketsBound'),
          ],
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.onToggleEnabled,
    required this.onRemove,
    required this.isFailSafeTarget,
    required this.onToggleFailSafeTarget,
    required this.onSendTest,
    required this.onSetSharedKey,
  });

  final PairedDevice device;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onRemove;
  final bool isFailSafeTarget;
  final ValueChanged<bool>? onToggleFailSafeTarget;
  final VoidCallback? onSendTest;
  final ValueChanged<String> onSetSharedKey;

  @override
  Widget build(BuildContext context) {
    final statusLabel =
        !device.isEnabled ? 'idle' : (device.isOnline ? 'online' : 'offline');
    final statusColor = !device.isEnabled
        ? Colors.amber
        : (device.isOnline ? Colors.green : Colors.red);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${device.name} (${device.platform.name})',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Switch(
                  value: device.isEnabled,
                  onChanged: onToggleEnabled,
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('${device.address}:${device.port}'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'ID: ${device.id}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (onToggleFailSafeTarget != null)
                  FilterChip(
                    selected: isFailSafeTarget,
                    onSelected: onToggleFailSafeTarget,
                    label: const Text('Use as fail-safe target'),
                  ),
                if (onSendTest != null)
                  OutlinedButton(
                    onPressed: onSendTest,
                    child: const Text('Send test now'),
                  ),
                OutlinedButton(
                  onPressed: () => _showPairDialog(context),
                  child: Text(device.isTrusted ? 'Update key' : 'Pair key'),
                ),
                TextButton(
                  onPressed: onRemove,
                  child: const Text('Remove'),
                ),
                Chip(
                  label: Text(device.isTrusted ? 'trusted' : 'untrusted'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: StatusIndicator(
                label: statusLabel,
                color: statusColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPairDialog(BuildContext context) async {
    var key = device.sharedKeyHint;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Pair key for ${device.name}'),
          content: TextFormField(
            initialValue: key,
            onChanged: (value) => key = value,
            decoration: const InputDecoration(
              labelText: 'Shared key',
              hintText: 'same key on both devices',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                onSetSharedKey(key);
                Navigator.of(context).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}
