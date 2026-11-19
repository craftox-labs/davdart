import 'package:davdart/davdart.dart';
import 'package:material_ui/material_ui.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'markdown_lite.dart';
import 'connect_dialog.dart';
import 'new_note_dialog.dart';
import 'new_space_dialog.dart';
import 'save_view_dialog.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key, required this.state, this.inDrawer = false});
  final AppState state;
  final bool inDrawer;

  void _close(BuildContext context) {
    if (inDrawer) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<TokensTheme>()!.tokens;
    final label = TextStyle(
      fontSize: 11,
      letterSpacing: .8,
      color: t.muted,
      fontWeight: FontWeight.w600,
    );

    Widget item(IconData icon, String text, bool on, VoidCallback tap) =>
        InkWell(
          onTap: tap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: on ? t.surface : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: on ? t.accent : t.muted),
                const SizedBox(width: 10),
                Expanded(child: Text(text, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        );

    final tree = <Widget>[];
    void walk(List<NoteNode> nodes, int depth) {
      for (final n in nodes) {
        final kids = n.children.isNotEmpty;
        final open = !state.collapsed.contains(n.note.uid);
        tree.add(
          InkWell(
            onTap: () {
              state.select(n.note.uid);
              _close(context);
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: EdgeInsets.fromLTRB(4 + depth * 14.0, 5, 8, 5),
              decoration: BoxDecoration(
                color: state.selectedUid == n.note.uid ? t.surface : null,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    child: kids
                        ? InkWell(
                            onTap: () => state.toggle(n.note.uid),
                            child: Icon(
                              open ? Icons.expand_more : Icons.chevron_right,
                              size: 16,
                              color: t.muted,
                            ),
                          )
                        : null,
                  ),
                  Expanded(
                    child: Text(
                      n.note.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        if (kids && open) walk(n.children, depth + 1);
      }
    }

    walk(state.tree.roots, 0);

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 12),
            child: state.spaces.isEmpty
                ? const Text(
                    'davdart',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  )
                : PopupMenuButton<String>(
                    key: const Key('space-menu'),
                    tooltip: 'Switch space',
                    padding: EdgeInsets.zero,
                    onSelected: (v) {
                      if (v == '\u0000new') {
                        _close(context);
                        showNewSpaceDialog(context, state);
                      } else {
                        state.switchSpace(v);
                        _close(context);
                      }
                    },
                    itemBuilder: (_) => [
                      for (final sp in state.spaces)
                        PopupMenuItem(
                          value: sp.id,
                          child: Text(
                            sp.name,
                            style: TextStyle(
                              fontWeight: sp.id == state.currentSpaceId
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: '\u0000new',
                        child: Text('New space…'),
                      ),
                    ],
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            state.currentSpaceName ?? 'davdart',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Icon(Icons.expand_more, size: 18, color: t.muted),
                      ],
                    ),
                  ),
          ),
          TextField(
            controller: state.searchController,
            onChanged: state.setQuery,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search',
              prefixIcon: Icon(Icons.search, size: 18, color: t.muted),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Tokens.radius),
                borderSide: BorderSide(color: t.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Tokens.radius),
                borderSide: BorderSide(color: t.line),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 4),
            child: Text('VIEWS', style: label),
          ),
          item(
            Icons.view_kanban_outlined,
            'Board',
            state.view == ViewMode.board,
            () {
              state.setView(ViewMode.board);
              state.select(null);
              _close(context);
            },
          ),
          item(Icons.list, 'List', state.view == ViewMode.list, () {
            state.setView(ViewMode.list);
            state.select(null);
            _close(context);
          }),
          for (final v in state.savedViews)
            Row(
              children: [
                Expanded(
                  child: item(Icons.bookmark_border, v.name, false, () {
                    state.applyView(v);
                    _close(context);
                  }),
                ),
                IconButton(
                  tooltip: 'Remove saved view',
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, color: t.muted),
                  onPressed: () => state.deleteView(v.name),
                ),
              ],
            ),
          if (state.hasFilter)
            item(Icons.bookmark_add_outlined, 'Save this view', false, () {
              showSaveViewDialog(context, state);
            }),
          if (state.canConnect) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 4),
              child: Text('SERVER', style: label),
            ),
            if (!state.connected)
              item(Icons.cloud_outlined, 'Connect server', false, () {
                _close(context);
                showConnectDialog(context, state);
              })
            else ...[
              item(
                Icons.sync,
                state.syncing ? 'Syncing…' : 'Sync now',
                false,
                state.sync,
              ),
              item(Icons.cloud_off_outlined, 'Disconnect', false, () {
                state.disconnect();
              }),
            ],
            if (state.connected && state.serverLabel != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 6, 0),
                child: Text(
                  state.serverLabel!,
                  style: TextStyle(fontSize: 11, color: t.muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (state.syncMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 6, 0),
                child: Text(
                  state.syncMessage!,
                  key: const Key('sync-message'),
                  style: TextStyle(fontSize: 11, color: t.muted),
                ),
              ),
          ],
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 4),
            child: Text('NOTES', style: label),
          ),
          if (state.editable)
            item(Icons.add, 'New note', false, () {
              _close(context);
              showNewNoteDialog(context, state);
            }),
          Expanded(child: ListView(children: tree)),
          if (state.tags.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 6, top: 8, bottom: 4),
              child: Text('TAGS', style: label),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in state.tags)
                  InkWell(
                    onTap: () => state.setTag(tag),
                    borderRadius: BorderRadius.circular(99),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: state.tag == tag ? t.surface : null,
                        border: Border.all(
                          color: state.tag == tag ? t.fg : t.line,
                        ),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          fontSize: 12,
                          color: state.tag == tag ? t.fg : t.muted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
