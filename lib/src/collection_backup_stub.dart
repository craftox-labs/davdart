/// No file system here (web): callers pass their own backup writer.
int writeBackupFiles(String dir, Map<String, String> files) =>
    throw UnsupportedError('no file system: pass a backupWriter');
