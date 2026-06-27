import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quorum_core/quorum_core.dart';
import 'package:window_manager/window_manager.dart';

import '../state/run_controller.dart';
import 'quorum_colors.dart';
import 'terminal_screen.dart' show TerminalBody;

/// The app's top-level surfaces.
enum _Surface { terminal, hub, settings }

extension _SurfaceLabel on _Surface {
  String get label => switch (this) {
        _Surface.terminal => 'Terminal',
        _Surface.hub => 'Hub',
        _Surface.settings => 'Settings',
      };
}

/// The application shell: owns the frameless window's custom title bar + lifecycle (the SOLE owner of
/// sidecar teardown on close), and hosts the Terminal / Hub / Settings surfaces via an IndexedStack.
/// Tab switching is synchronous (no animation) so goldens stay deterministic and run state is kept
/// alive across switches.
class QuorumShell extends ConsumerStatefulWidget {
  const QuorumShell({super.key});
  @override
  ConsumerState<QuorumShell> createState() => _QuorumShellState();
}

class _QuorumShellState extends ConsumerState<QuorumShell>
    with WidgetsBindingObserver, WindowListener {
  bool _closing = false;
  bool _isMaximized = false;
  _Surface _surface = _Surface.terminal;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    windowManager.isMaximized().then((m) {
      if (mounted && m != _isMaximized) setState(() => _isMaximized = m);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // --- Teardown reconciliation -----------------------------------------------------------------
  // onWindowClose is the SOLE owner of sidecar teardown. With setPreventClose(true) the OS WM_CLOSE
  // is routed here and the framework's didRequestAppExit may not fire, so we shut the sidecar down
  // here, then destroy() (which force-closes, bypassing preventClose WITHOUT re-emitting onWindowClose
  // — close() would loop forever). shutdown() is idempotent; the detached handler is a last-resort backstop.
  @override
  void onWindowClose() async {
    if (_closing) return;
    _closing = true;
    if (await windowManager.isPreventClose()) {
      await ref.read(runControllerProvider.notifier).shutdown();
      await windowManager.destroy();
    }
  }

  @override
  void onWindowMaximize() => setState(() => _isMaximized = true);
  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  @override
  Future<AppExitResponse> didRequestAppExit() async => AppExitResponse.exit; // onWindowClose owns teardown

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      ref.read(runControllerProvider.notifier).shutdown(); // backstop (idempotent)
    }
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: QC.bg,
      body: Column(
        children: [
          _TitleBar(
            isMaximized: _isMaximized,
            leading: _NavTabs(active: _surface, onSelect: (s) => setState(() => _surface = s)),
            onMinimize: () => windowManager.minimize(),
            onToggleMaximize: _toggleMaximize,
            onClose: () => windowManager.close(),
          ),
          Expanded(
            child: IndexedStack(
              index: _surface.index,
              children: const [
                TerminalSurface(),
                _Placeholder(title: 'Hub', subtitle: 'Multi-run history & launch — arriving in P2.4'),
                _Placeholder(
                    title: 'Settings', subtitle: 'Model Studio & API keys — arriving in P2.3'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The Terminal surface: watches the run + wires Run/Cancel into the pure 3-pane [TerminalBody].
/// Holds no window chrome (that lives in [QuorumShell]) so the golden harness can pump [TerminalBody]
/// in isolation. Owns the once-per-second tick that advances the header's elapsed timer while a run
/// is in flight — the [Timer] lives HERE, never in [TerminalBody], so it can't enter a golden test.
class TerminalSurface extends ConsumerStatefulWidget {
  const TerminalSurface({super.key});
  @override
  ConsumerState<TerminalSurface> createState() => _TerminalSurfaceState();
}

class _TerminalSurfaceState extends ConsumerState<TerminalSurface> {
  Timer? _tick;

  void _syncTick(RunPhase phase) {
    final running = phase == RunPhase.running;
    if (running && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {}); // re-derive the elapsed mm:ss from startedAtTs
      });
    } else if (!running && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(runControllerProvider);
    final ctrl = ref.read(runControllerProvider.notifier);
    _syncTick(state.phase); // start/stop the 1s ticker (no synchronous setState here)
    return TerminalBody(state: state, onRun: () => ctrl.start(), onCancel: ctrl.cancel);
  }
}

/// In-shell surface switcher, rendered at the left of the title bar.
class _NavTabs extends StatelessWidget {
  final _Surface active;
  final ValueChanged<_Surface> onSelect;
  const _NavTabs({required this.active, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 6),
        for (final s in _Surface.values)
          _NavTabButton(surface: s, active: s == active, onSelect: onSelect),
      ],
    );
  }
}

class _NavTabButton extends StatefulWidget {
  final _Surface surface;
  final bool active;
  final ValueChanged<_Surface> onSelect;
  const _NavTabButton({required this.surface, required this.active, required this.onSelect});
  @override
  State<_NavTabButton> createState() => _NavTabButtonState();
}

class _NavTabButtonState extends State<_NavTabButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final fg = active || _hover ? QC.textHi : QC.textMid;
    return Semantics(
      button: true,
      selected: active,
      label: widget.surface.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: () => widget.onSelect(widget.surface),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: active ? QC.accent : Colors.transparent, width: 2),
              ),
            ),
            child: Text(
              widget.surface.label,
              style: TextStyle(
                color: fg,
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A centred "coming soon" placeholder for the not-yet-built Hub / Settings surfaces.
class _Placeholder extends StatelessWidget {
  final String title;
  final String subtitle;
  const _Placeholder({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: QC.bg,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              style: const TextStyle(color: QC.textHi, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(color: QC.textLo, fontSize: 13)),
        ],
      ),
    );
  }
}

/// A slim frameless title bar: the surface switcher, a draggable strip (double-tap to maximize), and
/// Windows-style caption buttons. Shares the header's surface so it reads as headroom, not a separate bar.
class _TitleBar extends StatelessWidget {
  final bool isMaximized;
  final Widget? leading;
  final VoidCallback onMinimize;
  final VoidCallback onToggleMaximize;
  final VoidCallback onClose;
  const _TitleBar({
    required this.isMaximized,
    this.leading,
    required this.onMinimize,
    required this.onToggleMaximize,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      color: QC.surface1,
      child: Row(
        children: [
          ?leading,
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onDoubleTap: onToggleMaximize,
              child: const DragToMoveArea(child: SizedBox.expand()),
            ),
          ),
          _CaptionButton(icon: Icons.remove, tooltip: 'Minimize', onTap: onMinimize),
          _CaptionButton(
            icon: isMaximized ? Icons.filter_none : Icons.crop_square,
            iconSize: isMaximized ? 12 : 14,
            tooltip: isMaximized ? 'Restore' : 'Maximize',
            onTap: onToggleMaximize,
          ),
          _CaptionButton(icon: Icons.close, tooltip: 'Close', onTap: onClose, danger: true),
        ],
      ),
    );
  }
}

class _CaptionButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double iconSize;
  final bool danger;
  const _CaptionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.iconSize = 14,
    this.danger = false,
  });
  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final bg = _hover ? (widget.danger ? QC.down : QC.surface2) : Colors.transparent;
    final fg = _hover && widget.danger ? Colors.white : QC.textMid;
    return Semantics(
      button: true,
      label: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 46,
            height: 36,
            alignment: Alignment.center,
            color: bg,
            child: Icon(widget.icon, size: widget.iconSize, color: fg),
          ),
        ),
      ),
    );
  }
}
