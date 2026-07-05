import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The app's top-level surfaces, hosted by `QuorumShell` in an IndexedStack.
enum AppSurface { terminal, hub, settings }

extension AppSurfaceLabel on AppSurface {
  String get label => switch (this) {
        AppSurface.terminal => 'Terminal',
        AppSurface.hub => 'Hub',
        AppSurface.settings => 'Settings',
      };
}

/// The active surface. A provider (not local shell state) so other surfaces can navigate — e.g. the
/// Hub launches a run and switches to the Terminal to watch it.
final appSurfaceProvider =
    NotifierProvider<AppSurfaceController, AppSurface>(AppSurfaceController.new);

class AppSurfaceController extends Notifier<AppSurface> {
  @override
  AppSurface build() => AppSurface.terminal;
  void go(AppSurface s) => state = s;
}
