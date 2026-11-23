import 'dart:io';

import 'package:davdart/davdart.dart';
import 'package:davdart/src/collection_backup_io.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const _note = 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VJOURNAL\r\nUID:n1\r\n'
    'DTSTAMP:20260101T000000Z\r\nSUMMARY:N\r\nEND:VJOURNAL\r\nEND:VCALENDAR\r\n';

http.Response _ms(String inner) => http.Response(
    '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:" '
    'xmlns:c="urn:ietf:params:xml:ns:caldav">$inner</d:multistatus>',
    207);

String _coll(String name) =>
    '<d:response><d:href>/dav/bot/abc/</d:href><d:propstat><d:prop>'
    '<d:displayname>$name</d:displayname><d:resourcetype><d:collection/>'
    '<c:calendar/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK'
    '</d:status></d:propstat></d:response>';

/// Fake server with one collection /dav/bot/abc/ holding [items] notes.
class _Srv {
  _Srv(this.items);
  final int items;
  final log = <String>[];
  bool deleted = false;
  late final client = MockClient((r) async {
    log.add('${r.method} ${r.url.path}');
    if (r.method == 'PROPFIND' && r.url.path == '/dav/bot/') {
      return _ms(_coll('Work'));
    }
    if (r.method == 'REPORT') {
      final comp =
          RegExp(r'comp-filter name="(V\w+)"').allMatches(r.body).last.group(1);
      final body = (comp == 'VJOURNAL' || comp == 'VCALENDAR') && items > 0
          ? '<d:response><d:href>/dav/bot/abc/n1.ics</d:href><d:propstat><d:prop>'
              '<d:getetag>"e1"</d:getetag><c:calendar-data>${_note.replaceAll('<', '&lt;')}'
              '</c:calendar-data></d:prop><d:status>HTTP/1.1 200 OK</d:status>'
              '</d:propstat></d:response>'
          : '';
      return _ms(body);
    }
    if (r.method == 'DELETE') {
      deleted = true;
      return http.Response('', 204);
    }
    return http.Response('', 405);
  });
}

CollectionService _svc(_Srv s) => CollectionService(
    home: Uri.parse('http://h/dav/bot'),
    username: 'u',
    password: 'p',
    httpClient: s.client,
    now: () => DateTime.utc(2026, 11, 23, 10));

String _res(String name, String? data) =>
    '<d:response><d:href>/dav/bot/abc/$name</d:href><d:propstat><d:prop>'
    '<d:getetag>"e-$name"</d:getetag>'
    '${data == null ? '' : '<c:calendar-data>${data.replaceAll('<', '&lt;')}</c:calendar-data>'}'
    '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>';

String _ics(String comp, String uid) =>
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:$comp\r\nUID:$uid\r\n'
    'DTSTAMP:20260101T000000Z\r\nSUMMARY:S\r\nEND:$comp\r\nEND:VCALENDAR\r\n';

/// Fake server whose resources (name -> calendar-data, null = none) are
/// editable; typed REPORTs return the ones holding that component.
class _Srv2 {
  _Srv2(this.res);
  final Map<String, String?> res;
  final raw = <String, String>{};
  void Function()? onListed;
  var listings = 0;
  bool deleted = false;
  late final client = MockClient((r) async {
    if (r.method == 'PROPFIND' && r.url.path == '/dav/bot/') {
      return _ms(_coll('Work'));
    }
    if (r.method == 'REPORT') {
      final comp = RegExp(r'comp-filter name="(V\w+)"')
          .allMatches(r.body)
          .last
          .group(1)!;
      if (comp == 'VCALENDAR') {
        listings++;
        final out = _ms(res.entries.map((e) => _res(e.key, e.value)).join());
        if (listings == 1) onListed?.call();
        return out;
      }
      return _ms(res.entries
          .where((e) => e.value != null && e.value!.contains('BEGIN:$comp'))
          .map((e) => _res(e.key, e.value))
          .join());
    }
    if (r.method == 'GET') {
      final n = r.url.pathSegments.last;
      return raw.containsKey(n)
          ? http.Response(raw[n]!, 200)
          : http.Response('', 404);
    }
    if (r.method == 'DELETE') {
      deleted = true;
      return http.Response('', 204);
    }
    return http.Response('', 405);
  });
}

CollectionService _svc2(_Srv2 s) => CollectionService(
    home: Uri.parse('http://h/dav/bot'),
    username: 'u',
    password: 'p',
    httpClient: s.client,
    now: () => DateTime.utc(2026, 11, 23, 10));

void main() {
  final abc = Uri.parse('http://h/dav/bot/abc/');
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('davdart-coll'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('list, dry-run create and rename touch nothing', () async {
    final s = _Srv(0);
    final svc = _svc(s);
    expect((await svc.list()).single.name, 'Work');
    final c = await svc.create('New', dryRun: true);
    expect(c.dryRun, isTrue);
    final r = await svc.rename(abc, 'Other', dryRun: true);
    expect(r.changes.single, contains('"Work" -> "Other"'));
    expect(
        s.log.where(
            (l) => l.startsWith('MKCALENDAR') || l.startsWith('PROPPATCH')),
        isEmpty);
  });

  test('delete needs the exact name', () async {
    final s = _Srv(0);
    expect(() => _svc(s).delete(abc, confirmName: 'work', backupDir: tmp.path),
        throwsA(isA<CollectionSafetyException>()));
    expect(s.deleted, isFalse);
  });

  test('delete refuses a non-empty collection without the flag', () async {
    final s = _Srv(1);
    expect(() => _svc(s).delete(abc, confirmName: 'Work', backupDir: tmp.path),
        throwsA(isA<CollectionSafetyException>()));
    expect(s.deleted, isFalse);
    expect(tmp.listSync(), isEmpty);
  });

  test('dry-run delete reports the plan, writes nothing', () async {
    final s = _Srv(1);
    final r = await _svc(s).delete(abc,
        confirmName: 'Work',
        backupDir: tmp.path,
        allowNonEmpty: true,
        dryRun: true);
    expect(r.dryRun, isTrue);
    expect(r.itemCount, 1);
    expect(s.deleted, isFalse);
    expect(tmp.listSync(), isEmpty);
  });

  test('delete snapshots items first, then deletes', () async {
    final s = _Srv(1);
    final r = await _svc(s).delete(abc,
        confirmName: 'Work', backupDir: tmp.path, allowNonEmpty: true);
    expect(s.deleted, isTrue);
    final files = Directory(r.backupPath!).listSync();
    expect(files, hasLength(1));
    expect(File(files.single.path).readAsStringSync(), contains('UID:n1'));
    expect(r.backupPath, startsWith(tmp.path));
  });

  test('empty collection deletes without a backup', () async {
    final s = _Srv(0);
    final r =
        await _svc(s).delete(abc, confirmName: 'Work', backupDir: tmp.path);
    expect(s.deleted, isTrue);
    expect(r.backupPath, isNull);
  });

  test('deleteCollection reports a refusal', () async {
    final client = MockClient((_) async => http.Response('', 403));
    expect(
        () => CalDavClient.deleteCollection(abc,
            username: 'u', password: 'p', client: client),
        throwsA(isA<CalDavException>()));
  });

  test('probe reads capabilities', () async {
    final client = MockClient((r) async {
      if (r.method == 'OPTIONS') {
        return http.Response('', 200, headers: {
          'allow': 'GET, PROPFIND, PROPPATCH, MKCALENDAR',
          'dav': '1, calendar-access'
        });
      }
      return _ms(
          '<d:response><d:href>/dav/bot/abc/</d:href><d:propstat><d:prop>'
          '<d:supported-report-set><d:supported-report><d:report><d:sync-collection/>'
          '</d:report></d:supported-report></d:supported-report-set>'
          '<c:supported-calendar-component-set><c:comp name="VEVENT"/><c:comp name="VTODO"/>'
          '</c:supported-calendar-component-set></d:prop><d:status>HTTP/1.1 200 OK'
          '</d:status></d:propstat></d:response>');
    });
    final cap = await CollectionService(
            home: Uri.parse('http://h/dav/bot/'),
            username: 'u',
            password: 'p',
            httpClient: client)
        .probe(abc);
    expect(cap.syncCollection, isTrue);
    expect(cap.mkcalendar, isTrue);
    expect(cap.proppatch, isTrue);
    expect(cap.vjournal, isFalse);
    expect(cap.vtodo, isTrue);
    expect(cap.ctag, isNull);
    expect(cap.undetermined.keys, contains('ctag'));
    expect(cap.toJson()['components'], ['VEVENT', 'VTODO']);
  });

  test('probe fails soft', () async {
    final client = MockClient((_) async => throw http.ClientException('down'));
    final cap = await CollectionService(
            home: Uri.parse('http://h/dav/bot/'),
            username: 'u',
            password: 'p',
            httpClient: client)
        .probe(abc);
    expect(cap.syncCollection, isNull);
    expect(cap.components, isNull);
    expect(cap.undetermined.keys,
        containsAll(['syncCollection', 'components', 'mkcalendar']));
  });

  group('delete never discards what it did not back up', () {
    final abc = Uri.parse('http://h/dav/bot/abc/');
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('davdart-coll2'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('unparsable and empty resources abort the delete', () async {
      final s = _Srv2({
        'ok.ics': _ics('VJOURNAL', 'n1'),
        'bad.ics':
            'BEGIN:VCALENDAR\r\nBEGIN:VJOURNAL\r\nEND:VJOURNAL\r\nEND:VCALENDAR\r\n',
        'empty.ics': null,
      });
      await expectLater(
          _svc2(s).delete(abc,
              confirmName: 'Work', backupDir: tmp.path, allowNonEmpty: true),
          throwsA(isA<CollectionSafetyException>()
              .having((e) => e.message, 'message', contains('2 unreadable'))));
      expect(s.deleted, isFalse);
      expect(tmp.listSync(), isEmpty);
    });

    test('an unreadable-only collection counts as non-empty', () async {
      final s = _Srv2({'x.ics': null});
      await expectLater(
          _svc2(s).delete(abc,
              confirmName: 'Work', backupDir: tmp.path, allowUnreadable: true),
          throwsA(isA<CollectionSafetyException>()
              .having((e) => e.message, 'message', contains('1 items'))));
      expect(s.deleted, isFalse);
    });

    test('allowUnreadable backs up their raw bodies, then deletes', () async {
      final s = _Srv2({
        'ok.ics': _ics('VJOURNAL', 'n1'),
        'bad.ics': 'garbage',
        'empty.ics': null,
      })
        ..raw['bad.ics'] = 'garbage'
        ..raw['empty.ics'] = 'RAW-EMPTY';
      final r = await _svc2(s).delete(abc,
          confirmName: 'Work',
          backupDir: tmp.path,
          allowNonEmpty: true,
          allowUnreadable: true);
      expect(s.deleted, isTrue);
      expect(r.itemCount, 3);
      final texts = Directory(r.backupPath!)
          .listSync()
          .map((f) => File(f.path).readAsStringSync())
          .toList();
      expect(texts, hasLength(3));
      expect(texts, containsAll(['garbage', 'RAW-EMPTY']));
    });

    test('dry run with unreadable resources still refuses', () async {
      final s = _Srv2({'bad.ics': 'garbage'});
      await expectLater(
          _svc2(s).delete(abc,
              confirmName: 'Work',
              backupDir: tmp.path,
              allowNonEmpty: true,
              dryRun: true),
          throwsA(isA<CollectionSafetyException>()));
      expect(tmp.listSync(), isEmpty);
    });

    test('shared uids get separate backup files', () async {
      final s = _Srv2({
        'a.ics': _ics('VJOURNAL', 'same'),
        'b.ics': _ics('VTODO', 'same'),
        'c.ics': _ics('VEVENT', 'same'),
      });
      final r = await _svc2(s).delete(abc,
          confirmName: 'Work', backupDir: tmp.path, allowNonEmpty: true);
      final files = Directory(r.backupPath!).listSync();
      expect(files, hasLength(3));
      expect(r.itemCount, 3);
      expect(s.deleted, isTrue);
    });

    test('a short backup aborts before the DELETE', () async {
      final s = _Srv2({'a.ics': _ics('VJOURNAL', 'n1')});
      await expectLater(
          _svc2(s).delete(abc,
              confirmName: 'Work',
              backupDir: tmp.path,
              allowNonEmpty: true, backupWriter: (dir, files) {
            Directory(dir).createSync(recursive: true);
            return 0;
          }),
          throwsA(anything));
      expect(s.deleted, isFalse);
    });

    test('items created after the backup abort the delete', () async {
      final s = _Srv2({'a.ics': _ics('VJOURNAL', 'n1')});
      s.onListed = () {};
      final svc = _svc2(s);
      await expectLater(
          svc.delete(abc,
              confirmName: 'Work',
              backupDir: tmp.path,
              allowNonEmpty: true, backupWriter: (dir, files) {
            final n = writeBackupFiles(dir, files);
            s.res['late.ics'] = _ics('VJOURNAL', 'n2');
            return n;
          }),
          throwsA(isA<CollectionSafetyException>()
              .having((e) => e.message, 'message', contains('changed'))));
      expect(s.deleted, isFalse);
    });
  });
}
