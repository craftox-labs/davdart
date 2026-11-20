import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/data/space_catalog.dart';
import 'package:http/http.dart' as http;

/// A catalog as an existing install has it: the legacy Planning Space is
/// listed (a new, empty install has no Space at all).
SpaceCatalog catalogWithPlanning(
  KeyValueStorage storage, {
  NoteSource? planningSeed,
  Uri? davBase,
  http.Client? httpClient,
}) {
  final list = storage.read('davdart.spaces.v1');
  if (list == null || list.isEmpty) {
    storage.write(
      'davdart.spaces.v1',
      '[{"id":"${SpaceCatalog.planningId}","name":"Planning"}]',
    );
  }
  return SpaceCatalog(
    storage,
    planningSeed: planningSeed,
    davBase: davBase,
    httpClient: httpClient,
  );
}
