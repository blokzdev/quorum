import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quorum/state/app_surface.dart';
import 'package:quorum/ui/brand.dart';
import 'package:quorum/ui/quorum_colors.dart';
import 'package:quorum/ui/quorum_shell.dart';

/// P4.2c (shell-01): golden coverage for the frameless window chrome — the one surface that most
/// defines "premium desktop" and previously had ZERO golden coverage (the goldens rendered surface
/// bodies in isolation). ShellChrome is window_manager-decoupled, so it pumps cleanly here.
/// Capture find.byType(Scaffold), NOT the chrome directly — capturing a non-RepaintBoundary rasterises
/// text at a fractional offset (see settings_golden_test.dart / P4.2b).
Widget _wrap(AppSurface active, {bool maximized = false}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'Inter',
        scaffoldBackgroundColor: QC.bg,
        extensions: const [QuorumBrand.dark()],
      ),
      home: Scaffold(
        backgroundColor: QC.bg,
        body: Column(children: [
          ShellChrome(
            active: active,
            isMaximized: maximized,
            onSelect: (_) {},
            onMinimize: () {},
            onToggleMaximize: () {},
            onClose: () {},
          ),
          // A strip of body so the golden shows the title-bar → body seam.
          const Expanded(child: SizedBox.expand()),
        ]),
      ),
    );

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // window_manager's DragToMoveArea lives in the title bar; stub the channel so no call throws.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (_) async => null);
  });

  testWidgets('shell chrome — Hub active, windowed', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 150));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(AppSurface.hub));
    await tester.pumpAndSettle();

    // All three surface tabs + the three caption buttons render (minimize, maximize-square, close).
    expect(find.text('Terminal'), findsOneWidget);
    expect(find.text('Hub'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byIcon(Icons.remove), findsOneWidget);
    expect(find.byIcon(Icons.crop_square), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);

    await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/shell_chrome_hub.png'));
  });

  testWidgets('shell chrome — maximized shows the restore icon', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 150));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(AppSurface.terminal, maximized: true));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.filter_none), findsOneWidget); // restore glyph, not the square
    expect(find.byIcon(Icons.crop_square), findsNothing);

    await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/shell_chrome_max.png'));
  });

  testWidgets('shell — persistent disclaimer footer (hub-03)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 120));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'Inter',
        scaffoldBackgroundColor: QC.bg,
        extensions: const [QuorumBrand.dark()],
      ),
      home: const Scaffold(
        backgroundColor: QC.bg,
        body: Column(children: [Expanded(child: SizedBox.expand()), DisclaimerBar()]),
      ),
    ));
    await tester.pumpAndSettle();

    // The regulatory-posture disclaimer is present in the persistent chrome (hub-03).
    expect(find.textContaining('not financial advice'), findsOneWidget);
    await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/shell_disclaimer.png'));
  });
}
