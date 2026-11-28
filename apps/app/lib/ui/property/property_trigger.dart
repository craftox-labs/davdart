import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../note_menu.dart' show SheetPopoverController;
import '../popover_track.dart';
import '../theme.dart';

/// One property row's picker: the row is the popover's anchor on the wide
/// layout, and its sheet on the narrow one.
///
/// The popover is tracked ([TrackPopover]), so Esc closes it first and chords
/// stay swallowed while it is open. [picker] gets the control so a picked row
/// can close it. The narrow sheet carries [sheetKey] so tests can find it.
class PropertyTrigger extends StatefulWidget {
  const PropertyTrigger({
    super.key,
    required this.picker,
    required this.child,
    this.sheetKey,
  });

  final Widget Function(BuildContext context, FPopoverControl control) picker;
  final Widget child;
  final Key? sheetKey;

  @override
  State<PropertyTrigger> createState() => _PropertyTriggerState();
}

class _PropertyTriggerState extends State<PropertyTrigger>
    with TickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    if (narrowLayout(context)) {
      return FTappable(onPress: _openSheet, child: widget.child);
    }
    return TrackPopover(
      builder: (context, pc) => FPopover(
        control: pc,
        popoverBuilder: (context, _) => ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: t.sizes.dialogSm,
            maxWidth: t.sizes.dialog,
          ),
          child: widget.picker(context, pc),
        ),
        builder: (context, c, child) =>
            FTappable(onPress: c.toggle, child: child!),
        child: widget.child,
      ),
    );
  }

  /// The touch form of the same picker.
  Future<void> _openSheet() async {
    final navigator = Navigator.of(context);
    var open = true;
    final c = SheetPopoverController(
      vsync: this,
      close: () {
        if (!open) return;
        open = false;
        navigator.pop();
      },
    );
    try {
      await showFSheet<void>(
        context: context,
        side: FLayout.btt,
        mainAxisMaxRatio: 0.8,
        useSafeArea: true,
        builder: (ctx) => SingleChildScrollView(
          key: widget.sheetKey,
          child: widget.picker(ctx, FPopoverControl.managed(controller: c)),
        ),
      );
    } finally {
      open = false;
      c.dispose();
    }
  }
}
