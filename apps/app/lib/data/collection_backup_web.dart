import 'dart:js_interop';

import 'package:davdart/davdart.dart';
import 'package:web/web.dart' as web;

/// The web build has no file system: the snapshot is one .ics download.
String backupDirectory() => 'davdart-backup';

/// Joins every item into one .ics file and offers it as a download.
BackupWriter? backupWriter() => (dir, files) {
  final calendars = files.values.map((t) => t.trim()).join('\r\n');
  final blob = web.Blob(
    [calendars.toJS].toJS,
    web.BlobPropertyBag(type: 'text/calendar'),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = '${dir.split('/').last}.ics';
  a.click();
  web.URL.revokeObjectURL(url);
  return null;
};

const backupWhere = 'a download in your browser';

/// The browser cannot report whether the download was saved.
const backupNote =
    'Your browser will download a file. This app cannot tell '
    'whether it was saved: check the file is in your downloads before you '
    'confirm.';
