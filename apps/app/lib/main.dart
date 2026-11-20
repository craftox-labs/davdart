import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The app has its own right-click menus; keep the browser's from covering them.
  if (kIsWeb) BrowserContextMenu.disableContextMenu();
  runApp(DavdartApp());
}
