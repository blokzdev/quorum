import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'quorum_colors.dart';

/// Makes a custom (GestureDetector/InkWell) control keyboard-operable (P3.4a): Tab-focusable, activates
/// on Enter / Space, and paints a focus ring **only when focused** — via `foregroundDecoration`, which
/// overlays without affecting layout, so an unfocused render is byte-identical and the committed goldens
/// stay stable. Keep the mouse `onTap` on the wrapped child; pass the same callback as [onActivate].
///
/// A disabled control (`onActivate == null`) is skipped for focus and never paints a ring.
class Focusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onActivate;

  /// Match the wrapped control's own corner radius so the ring hugs its shape.
  final BorderRadius borderRadius;
  const Focusable({
    super.key,
    required this.child,
    required this.onActivate,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  State<Focusable> createState() => _FocusableState();
}

class _FocusableState extends State<Focusable> {
  bool _focused = false;

  // Enter (incl. numpad) and Space both activate — the two keys a keyboard user expects for a button.
  static const _shortcuts = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
  };

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onActivate != null;
    return FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      shortcuts: _shortcuts,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onActivate?.call();
          return null;
        }),
      },
      onShowFocusHighlight: (v) {
        if (mounted && v != _focused) setState(() => _focused = v);
      },
      child: Container(
        // foregroundDecoration paints OVER the child (no layout impact); null when unfocused → the
        // unfocused render is byte-identical to the bare child, so committed goldens stay stable.
        foregroundDecoration: _focused
            ? BoxDecoration(
                borderRadius: widget.borderRadius,
                border: Border.all(color: QC.accent, width: 2))
            : null,
        child: widget.child,
      ),
    );
  }
}
