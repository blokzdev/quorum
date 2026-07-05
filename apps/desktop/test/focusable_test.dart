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

  testWidgets('a disabled Focusable (onActivate == null) is neither focusable nor activatable',
      (tester) async {
    var count = 0;
    // A disabled instance next to an ENABLED sibling: Tab must skip the disabled one, and even if keys
    // were sent, the disabled instance has no callback to fire.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          const Focusable(
            onActivate: null,
            child: SizedBox(width: 120, height: 40, child: Text('disabled')),
          ),
          Focusable(
            onActivate: () => count++,
            child: const SizedBox(width: 120, height: 40, child: Text('enabled')),
          ),
        ]),
      ),
    ));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    // Tab landed on the ENABLED sibling (the disabled one is excluded from traversal), so activation
    // fired on it — proving the disabled instance was skipped, not merely the only candidate.
    expect(count, 2);
  });
}
