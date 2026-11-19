import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'parts.dart';

/// Searches every Space on this device and opens the chosen note.
Future<void> showSearchAllDialog(BuildContext context, AppState state) {
  final q = TextEditingController();
  List<SpaceHit>? hits;
  var run = 0;
  return showAppDialog(
    context,
    title: 'Search all spaces',
    content: StatefulBuilder(
      builder: (ctx, setState) {
        Future<void> search(String text) async {
          final mine = ++run;
          final found = await state.searchAllSpaces(text);
          if (mine != run) return; // a newer search is running
          setState(() => hits = text.trim().isEmpty ? null : found);
        }

        return SizedBox(
          height: 360,
          child: Column(
            children: [
              field(
                key: const Key('search-all-field'),
                controller: q,
                autofocus: true,
                hint: 'Search',
                onChange: search,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: hits == null
                    ? const SizedBox.shrink()
                    : hits!.isEmpty
                    ? const Center(child: Text('No matches'))
                    : ListView(
                        children: [
                          for (final h in hits!)
                            FItem(
                              key: Key('hit-${h.note.uid}'),
                              title: Text(h.note.summary),
                              subtitle: Text(h.space.name),
                              onPress: () {
                                Navigator.of(ctx).pop();
                                state.openHit(h);
                              },
                            ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    ),
    actions: [const CancelButton(label: 'Close')],
  );
}
