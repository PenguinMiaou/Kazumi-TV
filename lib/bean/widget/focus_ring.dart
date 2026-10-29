import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// Draws a ring around the focused control while a D-pad or keyboard drives
/// focus.
///
/// Material's focus state layers are faint, and an InkWell's highlight paints
/// under a card's cover image, so on a TV the focused item was often
/// invisible. The ring sits above every route, dialog and menu and follows the
/// control's own Material shape where it has one.
class FocusRing extends StatefulWidget {
  const FocusRing({super.key, required this.child});

  final Widget child;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing>
    with SingleTickerProviderStateMixin {
  /// Frames without movement before tracking stops; covers scroll-into-view
  /// and panel slide animations that follow a focus change.
  static const _settleFrames = 30;

  /// How far up the render tree a control's own Material may sit.
  static const _shapeSearchDepth = 8;

  final _ring = ValueNotifier<Path?>(null);
  late final Ticker _ticker = createTicker(_onTick);
  int _stableFrames = 0;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_track);
    FocusManager.instance.addHighlightModeListener(_onHighlightModeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_track);
    FocusManager.instance.removeHighlightModeListener(_onHighlightModeChanged);
    _ticker.dispose();
    _ring.dispose();
    super.dispose();
  }

  void _onHighlightModeChanged(FocusHighlightMode mode) => _track();

  void _track() {
    // Update right away so the ring lands with the focus change, then follow
    // any scroll or slide that the change sets off.
    _update();
    _stableFrames = 0;
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    if (_update()) {
      _stableFrames = 0;
    } else if (++_stableFrames > _settleFrames) {
      _ticker.stop();
    }
  }

  /// Returns whether the ring moved.
  bool _update() {
    final ring = _focusedRing();
    final previous = _ring.value;
    if (ring == null && previous == null) return false;
    if (ring != null &&
        previous != null &&
        ring.getBounds() == previous.getBounds()) {
      return false;
    }
    _ring.value = ring;
    return true;
  }

  Path? _focusedRing() {
    if (!mounted ||
        FocusManager.instance.highlightMode !=
            FocusHighlightMode.traditional) {
      return null;
    }
    final node = FocusManager.instance.primaryFocus;
    if (node == null || node is FocusScopeNode) {
      return null;
    }
    final target = node.context?.findRenderObject();
    final self = context.findRenderObject();
    if (target is! RenderBox ||
        !target.attached ||
        !target.hasSize ||
        self is! RenderBox ||
        !self.hasSize) {
      return null;
    }
    final area = self.size.width * self.size.height;
    final targetArea = target.size.width * target.size.height;
    // Whole-area nodes such as the player's key catcher are not a control.
    if (targetArea > area * 0.5) {
      return null;
    }
    final shape = _materialShapeOf(target, targetArea);
    if (shape != null) {
      return shape.clipper!
          .getClip(shape.size)
          .transform(shape.getTransformTo(self).storage);
    }
    final rect = MatrixUtils.transformRect(
      target.getTransformTo(self),
      Offset.zero & target.size,
    );
    return Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(12)));
  }

  /// The control's own Material (button, card, chip), not a page-level one.
  RenderPhysicalShape? _materialShapeOf(RenderBox target, double targetArea) {
    RenderObject? node = target;
    for (var depth = 0;
        depth < _shapeSearchDepth && node != null;
        depth++, node = node.parent) {
      if (node is RenderPhysicalShape &&
          node.hasSize &&
          node.clipper != null &&
          node.size.width * node.size.height <= targetArea * 1.5) {
        return node;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
        foregroundPainter: _RingPainter(_ring),
        // Moving the ring must not repaint the whole app on a weak GPU.
        child: RepaintBoundary(child: widget.child),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.ring) : super(repaint: ring);

  final ValueNotifier<Path?> ring;

  // A dark outline keeps the white ring readable on light covers.
  static final _outline = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 6
    ..color = Colors.black54;
  static final _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..color = Colors.white;

  @override
  void paint(Canvas canvas, Size size) {
    final path = ring.value;
    if (path == null) return;
    canvas
      ..drawPath(path, _outline)
      ..drawPath(path, _stroke);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.ring != ring;
}
