import 'package:flutter/material.dart';

typedef KazumiMenuBuilder =
    Widget Function(BuildContext context, VoidCallback? toggle);

const _menuItemStyle = ButtonStyle(
  minimumSize: WidgetStatePropertyAll(Size(144, 48)),
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
  alignment: AlignmentDirectional.centerStart,
  visualDensity: VisualDensity.standard,
);

class KazumiMenuButton extends StatelessWidget {
  const KazumiMenuButton({
    super.key,
    required this.builder,
    required this.menuChildren,
    this.controller,
    this.enabled = true,
    this.animated = false,
    this.crossAxisUnconstrained = true,
    this.onOpen,
    this.onClose,
    this.style,
  });

  final KazumiMenuBuilder builder;
  final List<Widget> menuChildren;
  final MenuController? controller;
  final bool enabled;

  /// Opt in only for menus that previously animated.
  final bool animated;
  final bool crossAxisUnconstrained;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;
  final MenuStyle? style;

  @override
  Widget build(BuildContext context) {
    return MenuButtonTheme(
      data: MenuButtonThemeData(
        // Submenu entries must use the same inset as ordinary menu items.
        style: _menuItemStyle.merge(MenuButtonTheme.of(context).style),
      ),
      child: MenuAnchor(
        controller: controller,
        consumeOutsideTap: true,
        crossAxisUnconstrained: crossAxisUnconstrained,
        animated: animated && !MediaQuery.disableAnimationsOf(context),
        onOpen: onOpen,
        onClose: onClose,
        style: style,
        menuChildren: [const _FocusFirstMenuItem(), ...menuChildren],
        builder: (context, controller, _) => builder(
          context,
          enabled && menuChildren.isNotEmpty
              ? () => controller.isOpen ? controller.close() : controller.open()
              : null,
        ),
      ),
    );
  }
}

/// Moves focus into a freshly opened menu.
///
/// [MenuAnchor] keeps its items in a separate focus scope and only enters it
/// for menu bars and submenu buttons, so with a custom anchor child a D-pad
/// remote could open a menu but never reach its items. The selected item
/// claims focus through autofocus; otherwise the first item gets it here.
class _FocusFirstMenuItem extends StatefulWidget {
  const _FocusFirstMenuItem();

  @override
  State<_FocusFirstMenuItem> createState() => _FocusFirstMenuItemState();
}

class _FocusFirstMenuItemState extends State<_FocusFirstMenuItem> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scope = FocusScope.of(context);
      if (scope.focusedChild != null) return;
      final policy = FocusTraversalGroup.maybeOf(context) ??
          ReadingOrderTraversalPolicy();
      policy.findFirstFocus(scope, ignoreCurrentFocus: true)?.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class KazumiMenuItem extends StatelessWidget {
  const KazumiMenuItem({
    super.key,
    required this.label,
    required this.onPressed,
    this.leadingIcon,
    this.selected,
    this.destructive = false,
    this.requestFocusOnHover = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? leadingIcon;

  /// Null for actions; a bool exposes single-choice selection semantics.
  final bool? selected;
  final bool destructive;
  final bool requestFocusOnHover;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = destructive
        ? colors.error
        : selected == true
        ? colors.primary
        : null;
    final foregroundColor = color == null
        ? null
        : WidgetStateProperty.resolveWith<Color?>(
            (states) => states.contains(WidgetState.disabled) ? null : color,
          );
    return MenuItemButton(
      onPressed: onPressed,
      autofocus: selected == true,
      requestFocusOnHover: requestFocusOnHover,
      style: ButtonStyle(
        foregroundColor: foregroundColor,
        iconColor: foregroundColor,
      ),
      leadingIcon: leadingIcon,
      child: Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: selected == null ? null : true,
        child: Text(label, textAlign: TextAlign.start),
      ),
    );
  }
}
