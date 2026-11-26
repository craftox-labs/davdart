import 'note.dart';

/// Tag of a Space's Personal container: a folder (not marked `kind-folder` in
/// spaces made by hand) that holds the individual's own items. Like the
/// Projects container it is hidden from the trees and lists; unlike it, its
/// contents are the Personal sections.
const personalTag = 'kind-personal';

/// Default title of a Personal container made by the app.
const personalTitle = 'Personal';

/// True for a folder tagged [personalTag].
bool isPersonalContainer(Note n) => n.categories.contains(personalTag);
