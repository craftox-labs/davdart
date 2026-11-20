import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// Which of the app's own popovers (dropdowns, date pickers) are showing.
/// Esc belongs to an open popover first. Popovers report in through
/// [TrackPopover], which owns their controller; nothing here looks at widget
/// types or walks the tree.
class PopoverTracker {
  PopoverTracker._();
  static final instance = PopoverTracker._();

  final _open = <Object, FPopoverController>{};
  bool _closedThisEvent = false;

  /// An open popover, or one that closed during the key event being handled.
  bool get active => _open.isNotEmpty || _closedThisEvent;

  void _report(Object owner, FPopoverController c) {
    if (c.status.isForwardOrCompleted) {
      // Re-insert so the most recently shown one is last.
      _open.putIfAbsent(owner, () => c);
    } else if (_open.remove(owner) != null) {
      _closedThisEvent = true;
      scheduleMicrotask(() => _closedThisEvent = false);
    }
  }

  void _forget(Object owner) => _open.remove(owner);

  /// Esc: closes the most recently opened popover. True when Esc was spent
  /// on a popover (just now, or by forui earlier in this same key event).
  bool dismiss() {
    if (_open.isNotEmpty) {
      _open.values.last.hide();
      return true;
    }
    return _closedThisEvent;
  }
}

/// Whether a tracked popover is showing: Esc belongs to it first.
bool popoverOpen() => PopoverTracker.instance.active;

/// Gives [builder] a popover control to pass to an FSelect or FDateField;
/// the tracker then knows while that popover is open and can close it.
class TrackPopover extends StatefulWidget {
  const TrackPopover({super.key, required this.builder});
  final Widget Function(BuildContext context, FPopoverControl control) builder;

  @override
  State<TrackPopover> createState() => _TrackPopoverState();
}

class _TrackPopoverState extends State<TrackPopover>
    with TickerProviderStateMixin {
  late final FPopoverController _controller = FPopoverController(vsync: this)
    ..addListener(_changed);
  late final FPopoverControl _control = FPopoverControl.managed(
    controller: _controller,
  );

  void _changed() => PopoverTracker.instance._report(this, _controller);

  @override
  void dispose() {
    PopoverTracker.instance._forget(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _control);
}
