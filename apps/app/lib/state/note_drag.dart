/// Where a dragged note started.
enum NoteDragSource { peek, tab, tree, list, board, search }

/// The payload of every note drag (the peek tab today; batch 2 reuses it to
/// drag entries onto folders or Spaces to move them). A drop target reads the
/// note's [uid] and may treat [source] differently.
class NoteDrag {
  const NoteDrag(this.uid, this.source);
  final String uid;
  final NoteDragSource source;
}

/// The payload of a main tab being dragged to a new place in the strip.
class TabDrag {
  const TabDrag(this.code);

  /// The tab's [DocTab.code].
  final String code;
}
