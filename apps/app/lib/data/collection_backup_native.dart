import 'dart:io';

import 'package:davdart/davdart.dart';

/// Where a native build saves a collection's ICS snapshot: one folder per
/// delete under the home folder (the system temp folder if there is none).
/// The default writer of the core service writes there.
String backupDirectory() {
  final env = Platform.environment;
  final home = env['HOME'] ?? env['USERPROFILE'];
  return '${home ?? Directory.systemTemp.path}/davdart-backups';
}

/// Null: use the core service's own file writer.
BackupWriter? backupWriter() => null;

/// Where the snapshot ends up, for the dialog.
const backupWhere = 'a folder on this device';

const backupNote = '';
