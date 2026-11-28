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
    this.onOpen,
    this.onOpenChanged,
    this.popoverWidth,
  });

  final Widget Function(BuildContext context, FPopoverController control)
  picker;
  final Widget child;
  final Key? sheetKey;

  /// Runs before the picker shows: text that is still typing is committed
  /// first, so the pick carries everything the field holds (a pick made while
  /// text is dirty flushes the text first).
  final Future<void> Function()? onOpen;

  /// Told when this row's popover opens or closes: an anchor that only shows
  /// on hover stays put while its popover is open.
  final ValueChanged<bool>? onOpenChanged;

  /// The popover's width, when its anchor is smaller than a picker popover
  /// (a day cell): the popover fits that width, right-aligned to the anchor
  /// and opening over it, so it never spills past the cell it was opened
  /// from.
  final double? popoverWidth;

  @override
  State<PropertyTrigger> createState() => _PropertyTriggerState();
}

class _PropertyTriggerState extends State<PropertyTrigger>
    with TickerProviderStateMixin {
  /// The tap region of this row's popover; stable while the row is.
  final _group = Object();

  FPopoverController? _popover;
  var _wasOpen = false;

  /// Follows the popover's controller (it is created by [TrackPopover], so it
  /// arrives with the first build) and reports its state.
  void _adopt(FPopoverController c) {
    if (identical(_popover, c)) return;
    _popover?.removeListener(_report);
    _popover = c..addListener(_report);
  }

  void _report() {
    final open = _popover?.status.isForwardOrCompleted ?? false;
    if (open == _wasOpen) return;
    _wasOpen = open;
    widget.onOpenChanged?.call(open);
  }

  @override
  void dispose() {
    _popover?.removeListener(_report);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    if (narrowLayout(context)) {
      return FTappable(onPress: () => _open(_openSheet), child: widget.child);
    }
    return TrackPopover(
      builder: (context, pc) => FPopover(
        control: pc,
        // A narrow anchor (a day cell) gets the popover over itself, its
        // right edge on the anchor's, so it stays inside the cell's column.
        childAnchor: widget.popoverWidth == null ? null : Alignment.topRight,
        popoverAnchor: widget.popoverWidth == null ? null : Alignment.topRight,
        // A picker that opens its own popover (a calendar, a select, a time
        // picker) shares this group, so tapping the inner one is not a tap
        // outside this one.
        groupId: _group,
        popoverBuilder: (context, c) {
          _adopt(c);
          return PropertyPopoverGroup(
            groupId: _group,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: widget.popoverWidth ?? t.sizes.dialogSm,
                maxWidth: widget.popoverWidth ?? t.sizes.dialog,
              ),
              child: widget.picker(context, c),
            ),
          );
        },
        builder: (context, c, child) =>
            FTappable(onPress: () => _open(c.toggle), child: child!),
        child: widget.child,
      ),
    );
  }

  /// Flushes what is pending, then shows [show] (the popover or the sheet).
  Future<void> _open(Future<void> Function() show) async {
    // A picker takes over from the field that had the focus: its text is
    // committed, and Esc then belongs to the popover, not to that field.
    FocusManager.instance.primaryFocus?.unfocus();
    await widget.onOpen?.call();
    if (!mounted) return;
    await show();
  }

  /// The narrow sheet is up (a second tap while it opens is the same sheet).
  var _sheetOpen = false;

  /// The touch form of the same picker.
  Future<void> _openSheet() async {
    if (_sheetOpen) return;
    _sheetOpen = true;
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
          child: widget.picker(ctx, c),
        ),
      );
    } finally {
      open = false;
      _sheetOpen = false;
      c.dispose();
    }
  }
}

/// The tap region a property picker's popover shares with the popovers it
/// opens itself. A picker reads it to pass to its fields, so tapping a date
/// calendar or a select inside a picker does not count as tapping outside it.
class PropertyPopoverGroup extends InheritedWidget {
  const PropertyPopoverGroup({
    super.key,
    required this.groupId,
    required super.child,
  });
  final Object groupId;

  /// The group of the picker above [context], or null in a sheet.
  static Object? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PropertyPopoverGroup>()
      ?.groupId;

  @override
  bool updateShouldNotify(PropertyPopoverGroup old) => groupId != old.groupId;
}
