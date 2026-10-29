import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// D-pad speed picker: a bar from the slowest to the fastest preset that
/// left / right move one step at a time. Each step applies straight away;
/// select or back closes the panel.
class PlayerSpeedPanel extends StatefulWidget {
  const PlayerSpeedPanel({
    super.key,
    required this.speed,
    required this.speeds,
    required this.onChanged,
  });

  final double speed;

  /// Ascending and evenly spaced; the bar snaps to these values.
  final List<double> speeds;
  final ValueChanged<double> onChanged;

  @override
  State<PlayerSpeedPanel> createState() => _PlayerSpeedPanelState();
}

class _PlayerSpeedPanelState extends State<PlayerSpeedPanel> {
  late double _speed = widget.speed.clamp(
    widget.speeds.first,
    widget.speeds.last,
  );

  static const Map<ShortcutActivator, Intent> _selectCloses =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.select): DismissIntent(),
        SingleActivator(LogicalKeyboardKey.enter): DismissIntent(),
      };

  String _label(double speed) => '${speed}x';

  double _snap(double value) {
    var nearest = widget.speeds.first;
    for (final speed in widget.speeds) {
      if ((speed - value).abs() < (nearest - value).abs()) nearest = speed;
    }
    return nearest;
  }

  void _setSpeed(double value) {
    final speed = _snap(value);
    if (speed == _speed) return;
    setState(() => _speed = speed);
    widget.onChanged(speed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hintStyle = theme.textTheme.labelMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    return Align(
      // Low on screen so the picture stays visible while adjusting.
      alignment: const Alignment(0, 0.72),
      child: Material(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          width: 480,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text('播放速度', style: theme.textTheme.titleMedium),
                    const Spacer(),
                    Text(
                      _label(_speed),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Shortcuts(
                  shortcuts: _selectCloses,
                  child: Slider(
                    autofocus: true,
                    value: _speed,
                    min: widget.speeds.first,
                    max: widget.speeds.last,
                    divisions: widget.speeds.length - 1,
                    label: _label(_speed),
                    onChanged: _setSpeed,
                  ),
                ),
                Row(
                  children: [
                    Text(_label(widget.speeds.first), style: hintStyle),
                    const Spacer(),
                    Text('← 慢   快 →', style: hintStyle),
                    const Spacer(),
                    Text(_label(widget.speeds.last), style: hintStyle),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
