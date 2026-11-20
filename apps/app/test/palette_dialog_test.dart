import 'package:davdart/davdart.dart';
import 'package:davdart_app/ui/command_palette.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

void main() {
  testWidgets('the palette chord never opens the palette over a dialog', (
    t,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final s = await pumpTasksApp(
      t,
      notes: [Note(uid: 'n1', summary: 'Note one', description: 'x')],
    );
    final ctx = t.element(find.byType(Text).first);
    showGeneralDialog<void>(
      context: ctx,
      pageBuilder: (_, _, _) => const Center(child: Text('Confirm?')),
    );
    await t.pumpAndSettle();
    expect(find.text('Confirm?'), findsOneWidget);
    // The page's key catcher still holds the focus behind the dialog.
    s.nav.node.requestFocus();
    await t.pump();
    expect(s.nav.node.hasPrimaryFocus, isTrue);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyK);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('palette-field')), findsNothing);
    expect(paletteOpen(ctx), isFalse);
    expect(find.text('Confirm?'), findsOneWidget);
  });
}
