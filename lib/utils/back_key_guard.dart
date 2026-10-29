import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keeps a remote's back press in one piece.
///
/// Android acts on back when the key comes up, while Kazumi closes panels,
/// menus and the player controls on the way down, which moves focus away
/// from whatever handled it. The key up then reached the platform unhandled
/// and left the page as well. A key up is swallowed whenever its key down was
/// handled anywhere in the app; otherwise back behaves as usual.
abstract final class BackKeyGuard {
  static bool _downHandled = false;

  static void install() {
    FocusManager.instance
      ..addEarlyKeyEventHandler(_early)
      ..addLateKeyEventHandler(_late);
  }

  static KeyEventResult _early(KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.goBack) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      // Assume it gets handled; the late handler clears this if not.
      _downHandled = true;
      return KeyEventResult.ignored;
    }
    final swallow = _downHandled;
    if (event is KeyUpEvent) _downHandled = false;
    return swallow ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  static KeyEventResult _late(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.goBack) {
      _downHandled = false;
    }
    return KeyEventResult.ignored;
  }
}
