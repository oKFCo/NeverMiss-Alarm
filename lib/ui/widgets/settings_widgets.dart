import 'package:flutter/material.dart';

class ToggleSettingTile extends StatelessWidget {
  const ToggleSettingTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
      ),
      onTap: () => onChanged(!value),
    );
  }
}

class DurationSettingRow extends StatefulWidget {
  const DurationSettingRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.unit = 'min',
    required this.onChanged,
    this.showInput = true,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final String unit;
  final ValueChanged<int> onChanged;
  final bool showInput;

  @override
  State<DurationSettingRow> createState() => _DurationSettingRowState();
}

class _DurationSettingRowState extends State<DurationSettingRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
  }

  @override
  void didUpdateWidget(covariant DurationSettingRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${widget.label}: ${widget.value} ${widget.unit}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Slider(
                min: widget.min.toDouble(),
                max: widget.max.toDouble(),
                divisions: widget.max - widget.min,
                label: '${widget.value} ${widget.unit}',
                value: widget.value.toDouble().clamp(
                      widget.min.toDouble(),
                      widget.max.toDouble(),
                    ),
                onChanged: (value) {
                  widget.onChanged(value.round());
                },
              ),
            ),
            if (widget.showInput) ...[
              const SizedBox(width: 12),
              SizedBox(
                width: 96,
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    isDense: true,
                    suffixText: widget.unit,
                  ),
                  onSubmitted: _submit,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  void _submit(String raw) {
    final parsed = int.tryParse(raw.trim());
    if (parsed == null) {
      _controller.text = widget.value.toString();
      return;
    }
    final normalized = parsed.clamp(widget.min, widget.max);
    _controller.text = normalized.toString();
    widget.onChanged(normalized);
  }
}
