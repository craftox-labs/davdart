# davdart

UI-free Dart core for notes and tasks over CalDAV. Notes are stored as iCalendar `VJOURNAL` resources.

- `Note`: uid, summary, description, categories, status, timestamps. Unmodelled properties (for example `ATTACH`) are kept on `extraLines` so a round trip does not lose data.
- `parseNotes` / `serializeNotes`: RFC 5545 line folding and text escaping, VJOURNAL only (other components are ignored).
- `CalDavClient`: list (REPORT), get, put and delete against one collection, with ETag preconditions (`ConflictException` on 412).
- `bin/davdart.dart`: small CLI (`list`, `add`, `rm`), configured by `DAVDART_URL`, `DAVDART_USER`, `DAVDART_PASSWORD`.

Plain Dart, no Flutter. `dart pub get && dart test`.
