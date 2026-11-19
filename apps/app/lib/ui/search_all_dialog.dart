import 'package:material_ui/material_ui.dart';

import '../state/app_state.dart';

/// Searches every Space on this device and opens the chosen note.
Future<void> showSearchAllDialog(BuildContext context, AppState state) {
  final q = TextEditingController();
  List<SpaceHit>? hits;
  var run = 0;
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Future<void> search(String text) async {
          final mine = ++run;
          final found = await state.searchAllSpaces(text);
          if (mine != run) return; // a newer search is running
          setState(() => hits = text.trim().isEmpty ? null : found);
        }

        return AlertDialog(
          title: const Text('Search all spaces'),
          content: SizedBox(
            width: 420,
            height: 360,
            child: Column(
              children: [
                TextField(
                  key: const Key('search-all-field'),
                  controller: q,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: 'Search'),
                  onChanged: search,
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
                              ListTile(
                                key: Key('hit-${h.note.uid}'),
                                dense: true,
                                title: Text(h.note.summary),
                                subtitle: Text(h.space.name),
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  state.openHit(h);
                                },
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    ),
  );
}
