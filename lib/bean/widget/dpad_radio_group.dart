import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A [RadioGroup] whose arrow keys move focus instead of the selection.
///
/// [RadioGroup] binds all four arrow keys to cycling the selected value, so a
/// D-pad remote can never move focus out of the group, and its traversal
/// policy skips unselected options. Restoring the app's default directional
/// focus shortcuts and a plain reading-order policy inside the group fixes
/// both; the focused option is still selected with the select / enter key.
class DpadRadioGroup<T> extends StatelessWidget {
  const DpadRadioGroup({
    super.key,
    this.groupValue,
    required this.onChanged,
    required this.child,
  });

  final T? groupValue;
  final ValueChanged<T?> onChanged;
  final Widget child;

  static const Map<ShortcutActivator, Intent> _arrowKeysMoveFocus =
      <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.arrowUp):
        DirectionalFocusIntent(TraversalDirection.up),
    SingleActivator(LogicalKeyboardKey.arrowDown):
        DirectionalFocusIntent(TraversalDirection.down),
    SingleActivator(LogicalKeyboardKey.arrowLeft):
        DirectionalFocusIntent(TraversalDirection.left),
    SingleActivator(LogicalKeyboardKey.arrowRight):
        DirectionalFocusIntent(TraversalDirection.right),
  };

  @override
  Widget build(BuildContext context) => RadioGroup<T>(
        groupValue: groupValue,
        onChanged: onChanged,
        child: FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: Shortcuts(shortcuts: _arrowKeysMoveFocus, child: child),
        ),
      );
}
