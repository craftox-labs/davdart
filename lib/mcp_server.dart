/// MCP front-end over the item and collection services. Not exported by
/// `davdart.dart`: it needs `dart:io` and `mcp_dart`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

import 'davdart.dart';
import 'io.dart';
import 'mcp_history.dart';

export 'mcp_history.dart';

/// Tool groups, selectable at start.
enum ToolGroup {
  /// overview, list, get and the list action of collections.
  read,

  /// create, update, move (and the history tool when a log is configured
  /// it belongs to read). Cannot delete: that is the delete group.
  write,

  /// delete (one item). Separate from write so a bot can be given edits
  /// without being able to remove anything.
  delete,

  /// collection create, rename, delete.
  admin;

  static Set<ToolGroup> parse(String csv) {
    final out = <ToolGroup>{};
    for (final p in csv.split(',')) {
      final s = p.trim().toLowerCase();
      if (s.isEmpty) continue;
      out.add(
        ToolGroup.values.firstWhere(
          (g) => g.name == s,
          orElse: () => throw FormatException(
            'unknown tool group "$s" (expected read, write, delete or admin)',
          ),
        ),
      );
    }
    if (out.isEmpty) throw const FormatException('--tools is empty');
    return out;
  }
}

const _kinds = ['note', 'task', 'event'];

const _collNote = ' Pass collection (href or exact name from the collections '
    'tool, action list; call it first) to work in another collection.';

final _statusNote = 'one of ${allowedStatuses.join(', ')}; '
    'review means shipped and waiting on tm to check; doing means partly shipped '
    'with work remaining; in_progress and in-progress mean doing, in_review, '
    'in-review, ready_for_review and to_review mean review, cancelled, duplicate and wontfix '
    'mean canceled, draft means backlog; any other word is refused';

String _slash(String p) => p.endsWith('/') ? p : '$p/';

/// True when [want] (an href, absolute or relative to [home]) names [c]. Only
/// collections the home lists can match, so no other path or host is reachable.
bool _sameHref(Uri home, Uri c, String want) {
  final u = home.resolve(want);
  return u.host == c.host &&
      u.port == c.port &&
      _slash(u.path) == _slash(c.path);
}

/// Builds an [McpServer] exposing the enabled [groups].
///
/// [collections] and [backupDir] are needed for the admin group; without a
/// backup directory the admin group is refused.
McpServer buildMcpServer({
  required ItemService items,
  CollectionService? collections,
  Set<ToolGroup> groups = const {ToolGroup.read},
  String? backupDir,
  HistoryLog? history,
  String? defaultWriter,
}) {
  if (groups.contains(ToolGroup.admin) && (backupDir ?? '').isEmpty) {
    throw ArgumentError(
      'the admin group needs a backup directory '
      '(--backup-dir): collection delete writes a backup first',
    );
  }
  final server = McpServer(
    const Implementation(name: 'davdart', version: '0.1.0'),
    options: const McpServerOptions(
      capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
    ),
  );
  final read = groups.contains(ToolGroup.read);
  final write = groups.contains(ToolGroup.write);
  final del = groups.contains(ToolGroup.delete);
  final admin = groups.contains(ToolGroup.admin);

  void tool(
    String name,
    String description,
    Map<String, JsonSchema> props,
    List<String> required,
    bool readOnly,
    Future<Object?> Function(_A a) fn, {
    bool destructive = false,
  }) {
    server.registerTool(
      name,
      description: description,
      inputSchema: JsonSchema.object(properties: props, required: required),
      annotations: ToolAnnotations(
        readOnlyHint: readOnly,
        destructiveHint: destructive,
        openWorldHint: false,
      ),
      callback: (args, extra) async {
        try {
          return _ok(await fn(_A(args)));
        } on _ArgError catch (e) {
          return _err('bad arguments: ${e.message}');
        } on ItemServiceException catch (e) {
          return _err(e.message);
        } on CollectionSafetyException catch (e) {
          return _err(
            e.message
                .replaceAll('allowNonEmpty', 'allow_non_empty')
                .replaceAll('allowUnreadable', 'allow_unreadable'),
          );
        } on ICalException catch (e) {
          return _err('cannot read server data: $e');
        } catch (e) {
          return _err('$e');
        }
      },
    );
  }

  // Item services per collection, built on demand with the configured
  // credentials and kept for this server (session) only.
  final byPath = <String, ItemService>{};
  final configuredPath = _slash(items.client.collection.path);

  /// The service for the `collection` argument: the configured collection when
  /// omitted, else a collection found by [CollectionService.list] under the
  /// home (href or exact display name). Anything else is refused.
  Future<ItemService> svcFor(_A a, [ItemKind? kind]) async {
    final q = a.string('collection');
    if (q == null || q.trim().isEmpty) return items;
    final svc = collections;
    if (svc == null) {
      throw ItemServiceException(
        'the collection argument needs collection access, which is not '
        'configured on this server',
      );
    }
    final all = await svc.list();
    final want = q.trim();
    CollectionInfo? hit;
    final byHref = all.where((c) => _sameHref(svc.home, c.href, want)).toList();
    if (byHref.length == 1) {
      hit = byHref.single;
    } else if (byHref.isEmpty) {
      final byName = all.where((c) => c.name == want).toList();
      if (byName.length > 1) {
        throw ItemServiceException(
          '${byName.length} collections are named '
          '"$want"; pass the href from the collections list',
        );
      }
      hit = byName.firstOrNull;
    }
    if (hit == null) {
      throw ItemServiceException(
        'no collection "$want" under the home; call '
        'the collections tool (action list) for names and hrefs',
      );
    }
    if (kind != null &&
        !(kind == ItemKind.note
            ? hit.holdsNotes
            : kind == ItemKind.task
                ? hit.holdsTasks
                : hit.holdsEvents)) {
      throw ItemServiceException(
        'collection "${hit.name}" does not hold '
        '${kind.name}s (it accepts: ${[
          if (hit.holdsNotes) 'notes',
          if (hit.holdsTasks) 'tasks',
          if (hit.holdsEvents) 'events'
        ].join(', ')})',
      );
    }
    final path = _slash(hit.href.path);
    if (path == configuredPath) return items;
    return byPath.putIfAbsent(
      path,
      () => ItemService(
        CalDavClient(
          collection: hit!.href,
          username: svc.username,
          password: svc.password,
          client: svc.httpClient,
        ),
      ),
    );
  }

  final kindS = JsonSchema.string(enumValues: _kinds, description: 'Item kind');
  final collS = JsonSchema.string(
    description: 'Collection href or exact name from the collections list '
        'action; default is the configured collection',
  );
  final idS = JsonSchema.string(
    description: 'uid, href or exact title (case-insensitive) of the item',
  );
  final dryS = JsonSchema.boolean(
    description: 'Preview the change without writing it',
  );
  final tagsS = JsonSchema.array(items: JsonSchema.string());
  final writerS = JsonSchema.string(
    description: 'Optional name of who is making this change (a bot or '
        'person label). Stored as the item\'s X-WRITER property and in the '
        'history log. Self-declared: not authentication, anyone with the '
        'token can claim any name; never rely on it for trust.',
  );
  final fallbackWriter = cleanWriter(defaultWriter);
  history?.ensureWritable();

  /// Runs a write, adding the writer stamp and the history entry. [id] set:
  /// the item's BEFORE snapshot (and, for a delete that adopts children,
  /// theirs) is logged before the write, which is refused if the log cannot
  /// be written. A create is logged once it has its uid. Dry runs change
  /// nothing and are not logged.
  Future<Object?> logged(
    String tool,
    _A a,
    ItemService svc,
    Future<Object?> Function(String? writer) run, {
    String? id,
    ItemKind? kind,
    bool adopt = false,
  }) async {
    final writer = cleanWriter(a.string('writer')) ?? fallbackWriter;
    final dry = a.boolean('dry_run') ?? false;
    final log = history;
    if (dry || log == null) return run(writer);
    final coll = _slash(svc.client.collection.path);
    Map<String, Object?> base(ItemData? it) => {
          'tool': tool,
          'collection': coll,
          if (it != null) ...{
            'uid': it.uid,
            'kind': it.kind.name,
            'title': it.title,
            if (it.href != null) 'href': it.href,
          },
          if (writer != null) 'writer': writer,
          'args': log.cleanArgs(a.m),
        };
    Future<String> ics(ItemData it) async => utf8.decode(
          await svc.client.getRawBytes(it.href!),
          allowMalformed: true,
        );
    String? entryId;
    if (id != null) {
      final item = await svc.get(id, kind: kind);
      final kids = <ItemData>[];
      if (adopt) {
        final page = await svc.list(
          under: item.uid,
          includeFolders: true,
          limit: 500,
        );
        kids.addAll(page.items.where((i) => i.parentUid == item.uid));
      }
      final entry = base(item);
      try {
        final before = <String>[await ics(item)];
        if (kids.isNotEmpty) {
          entry['children'] = [
            for (final k in kids) {'uid': k.uid, 'href': k.href},
          ];
          for (final k in kids) {
            before.add(await ics(k));
          }
        }
        entry['before'] = before;
        entryId = log.append(entry);
      } catch (e) {
        throw ItemServiceException(
          'history log failed ($e); the change was not made',
        );
      }
    }
    final Object? result;
    try {
      result = await run(writer);
    } catch (e) {
      if (entryId != null) {
        try {
          log.append({
            'tool': tool,
            'collection': coll,
            'failed': entryId,
            'error': '$e'.length > 500 ? '$e'.substring(0, 500) : '$e',
          });
        } catch (_) {}
      }
      rethrow;
    }
    if (entryId == null) {
      final it = result is Map ? result['item'] : null;
      final uid = it is Map ? it['uid'] : null;
      try {
        log.append({
          ...base(null),
          if (it is Map) ...{
            'uid': uid,
            'kind': it['kind'],
            'title': it['title'],
            if (it['href'] != null) 'href': it['href'],
          },
        });
      } catch (e) {
        throw ItemServiceException(
          'the item was created (uid $uid) but the history log failed: $e',
        );
      }
    }
    return result;
  }

  if (read) {
    tool(
      'overview',
      'Counts by kind, status and tag plus the folder tree (depth-limited). '
          'Start here to learn how a space is organised.$_collNote',
      {
        'collection': collS,
        'depth': JsonSchema.integer(
          minimum: 1,
          maximum: 6,
          description: 'Tree depth, default 2',
        ),
        'under': JsonSchema.string(
          description: 'Show only the subtree below this folder or item',
        ),
      },
      [],
      true,
      (a) async => (await (await svcFor(a)).overview(
        maxDepth: a.integer('depth') ?? 2,
        under: a.string('under'),
      ))
          .toJson(),
    );
    tool(
      'list',
      'Page through items (without bodies), oldest first. Filter by kind, '
          'tag, status ($_statusNote) or subtree. Use get for the body.'
          '$_collNote',
      {
        'collection': collS,
        'kind': kindS,
        'tag': JsonSchema.string(),
        'status': JsonSchema.string(),
        'under': JsonSchema.string(
          description: 'Only items below this folder or item',
        ),
        'folders': JsonSchema.boolean(description: 'Include folder notes'),
        'limit': JsonSchema.integer(
          minimum: 1,
          maximum: 500,
          description: 'Default 50',
        ),
        'offset': JsonSchema.integer(minimum: 0),
      },
      [],
      true,
      (a) async => (await (await svcFor(a, a.kind('kind'))).list(
        kind: a.kind('kind'),
        tag: a.string('tag'),
        status: a.string('status'),
        under: a.string('under'),
        includeFolders: a.boolean('folders') ?? false,
        limit: a.integer('limit') ?? 50,
        offset: a.integer('offset') ?? 0,
      ))
          .toJson(),
    );
    tool(
      'get',
      'One item in full, including its body and etag.$_collNote',
      {'collection': collS, 'id': idS, 'kind': kindS},
      ['id'],
      true,
      (a) async => (await (await svcFor(
        a,
        a.kind('kind'),
      ))
              .get(a.req('id'), kind: a.kind('kind')))
          .toJson(),
    );
    final log = history;
    if (log != null) {
      tool(
        'history',
        'Recent writes made through this server, newest first: time, tool, '
            'collection, item, writer, arguments. Filter by collection and '
            'item id (uid, href or exact title). The BEFORE snapshots (ICS '
            'of the item as it was) are left out unless include_bodies. '
            'Writer names are self-declared.$_collNote',
        {
          'collection': collS,
          'id': idS,
          'limit': JsonSchema.integer(
            minimum: 1,
            maximum: 200,
            description: 'Default 20',
          ),
          'include_bodies': JsonSchema.boolean(
            description: 'Include BEFORE snapshots and full arguments',
          ),
        },
        [],
        true,
        (a) async {
          String? coll;
          if (a.string('collection') != null &&
              a.string('collection')!.trim().isNotEmpty) {
            coll = _slash((await svcFor(a)).client.collection.path);
          }
          final entries = log.read(
            collection: coll,
            item: a.string('id'),
            limit: a.integer('limit') ?? 20,
            bodies: a.boolean('include_bodies') ?? false,
          );
          return {'count': entries.length, 'entries': entries};
        },
      );
    }
  }

  if (write) {
    tool(
      'create',
      'Create a note, task or event. Folders are notes with folder=true. '
          'due is for tasks; priority for tasks and notes (1-4 high, 5 medium, '
          '6-9 low); start, end and location for events (an event needs '
          'start). status: $_statusNote. Dates: YYYY-MM-DD or '
          'YYYY-MM-DDTHH:MM[:SS][Z].$_collNote',
      {
        'collection': collS,
        'kind': kindS,
        'title': JsonSchema.string(),
        'body': JsonSchema.string(),
        'tags': tagsS,
        'status': JsonSchema.string(),
        'parent': JsonSchema.string(description: 'Parent folder or item'),
        'folder': JsonSchema.boolean(),
        'due': JsonSchema.string(),
        'priority': JsonSchema.integer(minimum: 0, maximum: 9),
        'start': JsonSchema.string(),
        'end': JsonSchema.string(),
        'location': JsonSchema.string(),
        'writer': writerS,
        'dry_run': dryS,
      },
      ['kind', 'title'],
      false,
      (a) async {
        final svc = await svcFor(a, a.kind('kind'));
        return logged(
          'create',
          a,
          svc,
          (w) async => (await svc.create(
            a.kind('kind')!,
            a.req('title'),
            writer: w,
            body: a.string('body') ?? '',
            tags: a.strings('tags'),
            status: a.string('status'),
            parent: a.string('parent'),
            folder: a.boolean('folder') ?? false,
            due: a.string('due'),
            priority: a.integer('priority'),
            start: a.string('start'),
            end: a.string('end'),
            location: a.string('location'),
            dryRun: a.boolean('dry_run') ?? false,
          ))
              .toJson(),
        );
      },
    );
    tool(
      'update',
      'Change fields of one item; only the fields you pass change. Tags: '
          'tags_add, tags_remove or tags_set (kind-projects and kind-folder '
          'cannot be added or removed; create folders with create). status ($_statusNote; empty '
          'string clears it on notes and events). due is for tasks (empty '
          'clears); priority for tasks and notes (1-4 high, 5 medium, 6-9 '
          'low; -1 clears; a note keeps it as a "priority: high|medium|low" '
          'body line); start, end and location for events.$_collNote',
      {
        'collection': collS,
        'id': idS,
        'kind': kindS,
        'title': JsonSchema.string(),
        'body': JsonSchema.string(),
        'tags_add': tagsS,
        'tags_remove': tagsS,
        'tags_set': tagsS,
        'status': JsonSchema.string(),
        'due': JsonSchema.string(),
        'priority': JsonSchema.integer(minimum: -1, maximum: 9),
        'start': JsonSchema.string(),
        'end': JsonSchema.string(),
        'location': JsonSchema.string(),
        'writer': writerS,
        'dry_run': dryS,
      },
      ['id'],
      false,
      (a) async {
        final svc = await svcFor(a, a.kind('kind'));
        return logged(
          'update',
          a,
          svc,
          (w) => _update(svc, a, w),
          id: a.req('id'),
          kind: a.kind('kind'),
        );
      },
    );
    tool(
      'rank',
      'Reorder a note or task inside its status column (the board order: '
          'manual rank, then priority, due, creation). Give exactly one of '
          'position "top" or "bottom", before or after (another item in the '
          'same status), or position "none" to drop its manual rank so '
          'priority and due decide again. Items without a status cannot be '
          'ranked. May also write neighbours whose rank must change. '
          'Returns the column order after.$_collNote',
      {
        'collection': collS,
        'id': idS,
        'position': JsonSchema.string(
          description: '"top", "bottom" or "none" (clear the rank)',
        ),
        'before': JsonSchema.string(
          description: 'uid, href or exact title of the item to go above',
        ),
        'after': JsonSchema.string(
          description: 'uid, href or exact title of the item to go below',
        ),
        'writer': writerS,
        'dry_run': dryS,
      },
      ['id'],
      false,
      (a) async {
        final pos = a.string('position')?.toLowerCase();
        if (pos != null && !const {'top', 'bottom', 'none'}.contains(pos)) {
          throw ItemServiceException(
            'position must be top, bottom or none (or pass before/after)',
          );
        }
        final svc = await svcFor(a);
        return logged(
          'rank',
          a,
          svc,
          (w) async => (await svc.rankItem(
            a.req('id'),
            top: pos == 'top',
            bottom: pos == 'bottom',
            clear: pos == 'none',
            before: a.string('before'),
            after: a.string('after'),
            writer: w,
            dryRun: a.boolean('dry_run') ?? false,
          ))
              .toJson(),
          id: a.req('id'),
        );
      },
    );
    tool(
      'move',
      'Move an item under a parent folder or item, or to the top level '
          '(omit parent or pass "top"). Cycles are refused.$_collNote',
      {
        'collection': collS,
        'id': idS,
        'parent': JsonSchema.string(),
        'writer': writerS,
        'dry_run': dryS,
      },
      ['id'],
      false,
      (a) async {
        final p = a.string('parent');
        final svc = await svcFor(a);
        return logged(
          'move',
          a,
          svc,
          (w) async => (await svc.move(
            a.req('id'),
            p == null || p.toLowerCase() == 'top' ? null : p,
            writer: w,
            dryRun: a.boolean('dry_run') ?? false,
          ))
              .toJson(),
          id: a.req('id'),
        );
      },
    );
  }

  if (del) {
    tool(
      'delete',
      'Delete one item. Children move up to its parent unless '
          'adopt_children is false. There is no trash: use dry_run first.$_collNote',
      {
        'collection': collS,
        'id': idS,
        'kind': kindS,
        'adopt_children': JsonSchema.boolean(description: 'Default true'),
        'writer': writerS,
        'dry_run': dryS,
      },
      ['id'],
      false,
      (a) async {
        final svc = await svcFor(a, a.kind('kind'));
        final adopt = a.boolean('adopt_children') ?? true;
        return logged(
          'delete',
          a,
          svc,
          (w) async => (await svc.delete(
            a.req('id'),
            kind: a.kind('kind'),
            adoptChildren: adopt,
            writer: w,
            dryRun: a.boolean('dry_run') ?? false,
          ))
              .toJson(),
          id: a.req('id'),
          kind: a.kind('kind'),
          adopt: adopt,
        );
      },
      destructive: true,
    );
  }

  if (read || admin) {
    final svc = collections;
    final actions = [
      if (read) 'list',
      if (admin) ...['create', 'rename', 'delete'],
    ];
    tool(
      'collections',
      'Manage server collections (calendars). action: ${actions.join(', ')}. '
          'delete needs confirm = the exact collection name, refuses a '
          'non-empty collection unless allow_non_empty, and writes an ICS '
          'backup first (the path is returned). Rights and sharing cannot '
          'be changed over CalDAV.',
      {
        'action': JsonSchema.string(
          enumValues: ['list', 'create', 'rename', 'delete'],
        ),
        'name': JsonSchema.string(description: 'create: display name'),
        'href': JsonSchema.string(
          description: 'rename/delete: collection href from list',
        ),
        'new_name': JsonSchema.string(description: 'rename: new name'),
        'confirm': JsonSchema.string(
          description: 'delete: exact current collection name',
        ),
        'allow_non_empty': JsonSchema.boolean(),
        'allow_unreadable': JsonSchema.boolean(),
        'dry_run': dryS,
      },
      ['action'],
      !admin,
      destructive: admin,
      (a) async {
        if (svc == null) {
          throw ItemServiceException('collection management is not configured');
        }
        final action = a.req('action');
        if (!actions.contains(action)) {
          throw ItemServiceException(
            action == 'list' ||
                    action == 'create' ||
                    action == 'rename' ||
                    action == 'delete'
                ? 'collections "$action" is not enabled here (enabled: '
                    '${actions.join(', ')}); start the server with the admin '
                    'group to allow it'
                : 'unknown action "$action" (expected ${actions.join(', ')})',
          );
        }
        final dry = a.boolean('dry_run') ?? false;
        switch (action) {
          case 'list':
            return {
              'collections': [
                for (final c in await svc.list())
                  {
                    'name': c.name,
                    'href': c.href.toString(),
                    'notes': c.holdsNotes,
                    'tasks': c.holdsTasks,
                    'events': c.holdsEvents,
                  },
              ],
            };
          case 'create':
            return (await svc.create(a.req('name'), dryRun: dry)).toJson();
          case 'rename':
            return (await svc.rename(
              svc.home.resolve(a.req('href')),
              a.req('new_name'),
              dryRun: dry,
            ))
                .toJson();
          default:
            return (await svc.delete(
              svc.home.resolve(a.req('href')),
              confirmName: a.req('confirm'),
              backupDir: backupDir!,
              allowNonEmpty: a.boolean('allow_non_empty') ?? false,
              allowUnreadable: a.boolean('allow_unreadable') ?? false,
              dryRun: dry,
            ))
                .toJson();
        }
      },
    );
  }
  return server;
}

/// update = fields, then tags, status, due, priority, in that order, on the
/// item resolved once up front.
Future<Object?> _update(ItemService items, _A a, String? writer) async {
  final dry = a.boolean('dry_run') ?? false;
  final item = await items.get(a.req('id'), kind: a.kind('kind'));
  final id = item.uid;
  final kind = item.kind;
  bool has(String k) => a.has(k);
  if (kind != ItemKind.task && has('due')) {
    throw ItemServiceException(
      'due applies to tasks only; '
      '"${item.title}" is a ${kind.name}',
    );
  }
  if (kind == ItemKind.event && has('priority')) {
    throw ItemServiceException(
      'priority applies to tasks and notes only; '
      '"${item.title}" is an event',
    );
  }
  if (kind != ItemKind.event &&
      (has('start') || has('end') || has('location'))) {
    throw ItemServiceException(
      'start, end and location apply to events '
      'only; "${item.title}" is a ${kind.name}',
    );
  }
  final changes = <String>[];
  var last = item;
  void take(ItemChange c) {
    changes.addAll(c.changes);
    last = c.item;
  }

  if (has('title') ||
      has('body') ||
      has('start') ||
      has('end') ||
      has('location')) {
    take(
      await items.update(
        id,
        kind: kind,
        title: a.string('title'),
        body: a.string('body'),
        start: a.string('start'),
        end: a.string('end'),
        location: a.string('location'),
        writer: writer,
        dryRun: dry,
      ),
    );
  }
  if (has('tags_add') || has('tags_remove') || has('tags_set')) {
    take(
      await items.setTags(
        id,
        kind: kind,
        set: has('tags_set') ? a.strings('tags_set') : null,
        add: a.strings('tags_add'),
        remove: a.strings('tags_remove'),
        writer: writer,
        dryRun: dry,
      ),
    );
  }
  if (has('status')) {
    final s = a.string('status')!;
    take(
      await items.setStatus(
        id,
        s.isEmpty ? null : s,
        kind: kind,
        writer: writer,
        dryRun: dry,
      ),
    );
  }
  if (has('due')) {
    final d = a.string('due')!;
    take(
      await items.setDue(id, d.isEmpty ? null : d, writer: writer, dryRun: dry),
    );
  }
  if (has('priority')) {
    final p = a.integer('priority')!;
    take(
      await items.setPriority(
        id,
        p < 0 ? null : p,
        kind: kind,
        writer: writer,
        dryRun: dry,
      ),
    );
  }
  return ItemChange('update', dry, changes, last).toJson();
}

CallToolResult _ok(Object? v) =>
    CallToolResult(content: [TextContent(text: jsonEncode(v))]);

CallToolResult _err(String m) =>
    CallToolResult(content: [TextContent(text: 'error: $m')], isError: true);

class _ArgError implements Exception {
  _ArgError(this.message);
  final String message;
}

/// Typed access to tool arguments with clear errors.
class _A {
  _A(this.m);
  final Map<String, dynamic> m;

  bool has(String k) => m[k] != null;

  String? string(String k) {
    final v = m[k];
    if (v == null) return null;
    if (v is! String) throw _ArgError('"$k" must be a string');
    return v;
  }

  String req(String k) {
    final v = string(k);
    if (v == null) throw _ArgError('"$k" is required');
    return v;
  }

  int? integer(String k) {
    final v = m[k];
    if (v == null) return null;
    if (v is int) return v;
    if (v is double && v == v.truncate()) return v.toInt();
    throw _ArgError('"$k" must be an integer');
  }

  bool? boolean(String k) {
    final v = m[k];
    if (v == null) return null;
    if (v is! bool) throw _ArgError('"$k" must be true or false');
    return v;
  }

  List<String> strings(String k) {
    final v = m[k];
    if (v == null) return const [];
    if (v is! List || v.any((e) => e is! String)) {
      throw _ArgError('"$k" must be a list of strings');
    }
    return v.cast<String>();
  }

  ItemKind? kind(String k) {
    final s = string(k);
    return s == null ? null : ItemKind.parse(s);
  }
}

/// Builds the services from the shared config loader (`loadConfig`), or
/// throws a [StateError] naming the missing keys (never their values).
({ItemService items, CollectionService collections}) servicesFromConfig([
  Map<String, String>? config,
]) {
  final cfg = config ?? loadConfig();
  final url = cfg['url'], user = cfg['user'], pass = cfg['password'];
  final missing = [
    if (url == null) 'url',
    if (user == null) 'user',
    if (pass == null) 'password',
  ];
  if (missing.isNotEmpty) {
    throw StateError(
      'missing config: ${missing.join(', ')} (see loadConfig: '
      '~/.config/davdart/credentials or DAVDART_URL, DAVDART_USER, '
      'DAVDART_PASSWORD)',
    );
  }
  final coll = Uri.parse(url!);
  final client = CalDavClient(
    collection: coll,
    username: user!,
    password: pass!,
  );
  // The collections' home is the parent of the configured collection unless
  // the config names it (`home`).
  final Uri home;
  if (cfg['home'] != null) {
    home = Uri.parse(cfg['home']!);
  } else {
    final segs = coll.pathSegments.where((s) => s.isNotEmpty).toList();
    home = coll.replace(
      path: '/${segs.take(segs.length > 1 ? segs.length - 1 : 0).join('/')}/',
    );
  }
  return (
    items: ItemService(client),
    collections: CollectionService(home: home, username: user, password: pass),
  );
}

/// Serves [serverFactory] over Streamable HTTP at `/mcp`, with a bearer token
/// required on every request. Returns the running server; its `boundPort`
/// gives the port when [port] is 0.
///
/// Failed auth is answered 403 by mcp_dart (no 401 unless OAuth metadata is
/// configured, which would advertise an authorisation server we do not have).
StreamableMcpServer buildHttpServer(
  McpServer Function() serverFactory, {
  required String token,
  int port = 0,
  String host = '127.0.0.1',
  Set<String> allowedHosts = const {},
}) {
  if (token.isEmpty) throw ArgumentError('a bearer token is required');
  final expected = utf8.encode('Bearer $token');
  return StreamableMcpServer(
    serverFactory: (_) => serverFactory(),
    host: host,
    port: port,
    enableJsonResponse: true,
    allowedHosts: allowedHosts.isEmpty
        ? null
        : {host, 'localhost', '127.0.0.1', ...allowedHosts},
    authenticator: (req) {
      final got = utf8.encode(req.headers.value('authorization') ?? '');
      if (got.length != expected.length) return false;
      var diff = 0;
      for (var i = 0; i < got.length; i++) {
        diff |= got[i] ^ expected[i];
      }
      return diff == 0;
    },
  );
}
