import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quorum/ui/focusable.dart';

void main() {
  testWidgets('Focusable is Tab-reachable and activates on Enter AND Space (P3.4a)', (tester) async {
    var count = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Focusable(
            onActivate: () => count++,
            child: const SizedBox(width: 120, height: 40, child: Text('tap me')),
          ),
        ),
      ),
    ));

    // Tab moves keyboard focus onto the control (it was unreachable before P3.4a).
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(count, 1, reason: 'Enter activates');

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(count, 2, reason: 'Space activates');
  });

  testWidgets('a disabled Focusable (onActivate == null) is not keyboard-focusable', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Focusable(
            onActivate: null,
            child: SizedBox(width: 120, height: 40, child: Text('disabled')),
          ),
        ),
      ),
    ));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    // Nothing focusable → focus stays null (or off the control); no activation possible.
    final focused = tester.binding.focusManager.primaryFocus;
    expect(focused?.context?.widget is Focusable, isFalse);
  });
}
