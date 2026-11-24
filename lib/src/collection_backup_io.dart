import 'dart:io';

/// Writes each entry of [files] (file name to text) into [dir], creating it,
/// then checks that exactly that many files are there.
int writeBackupFiles(String dir, Map<String, String> files) {
  final d = Directory(dir)..createSync(recursive: true);
  files
      .forEach((name, text) => File('${d.path}/$name').writeAsStringSync(text));
  for (final name in files.keys) {
    if (File('${d.path}/$name').lengthSync() == 0) {
      throw FileSystemException('backup file $name is empty', dir);
    }
  }
  final n = d.listSync().whereType<File>().length;
  if (n != files.length) {
    throw FileSystemException(
        'backup holds $n files, expected ${files.length}', dir);
  }
  return n;
}
