import 'package:flutter/services.dart';

import 'app_action.dart';

/// Whether [label] (a shortcut label such as `j`, `g g`, `Enter`) is a bare
/// key or sequence the key handler binds. Chords with Ctrl, Cmd or Alt are
/// bound where they are wired, not here.
bool isBareKeyLabel(String label) =>
    !label.contains('Ctrl+') &&
    !label.contains('Cmd+') &&
    !label.contains('Alt+');

/// A bare key that is a single printable character is a Vim key: it goes
/// away when the setting is off. Named keys (Up, Enter, Esc) always work.
bool isVimLabel(String label) => label.split(' ').any((t) => t.length == 1);

/// The binding table: key sequences to actions, built from the registry's
/// shortcut labels (one source of truth). A sequence is its tokens joined by
/// spaces, `g t`.
class KeyBindings {
  KeyBindings(Iterable<AppAction> actions, {required bool vim}) {
    for (final a in actions) {
      for (final s in a.shortcuts) {
        if (!isBareKeyLabel(s)) continue;
        if (!vim && isVimLabel(s)) continue;
        _map.putIfAbsent(s, () => a);
        final parts = s.split(' ');
        for (var i = 1; i < parts.length; i++) {
          _prefixes.add(parts.sublist(0, i).join(' '));
        }
      }
    }
  }

  final Map<String, AppAction> _map = {};
  final Set<String> _prefixes = {};

  /// What typing [token] after the pending [keys] does: run an action, wait
  /// for more keys, or nothing.
  KeyStep resolve(List<String> keys, String token) {
    final seq = [...keys, token].join(' ');
    final a = _map[seq];
    if (a != null) return KeyStep.run(a);
    if (_prefixes.contains(seq)) return KeyStep.wait(seq.split(' '));
    return const KeyStep.none();
  }

  bool get isEmpty => _map.isEmpty;
}

class KeyStep {
  const KeyStep.none() : action = null, keys = null;
  const KeyStep.wait(List<String> this.keys) : action = null;
  const KeyStep.run(AppAction this.action) : keys = null;
  final AppAction? action;
  final List<String>? keys;
}

/// The token of key event [e]: a character (`j`, `G`, `?`) or a key name
/// (`Up`, `Down`, `Left`, `Right`, `Enter`, `Esc`, `Home`, `End`); null for
/// keys the handler does not use. [shift] is the shift state.
String? keyToken(KeyEvent e, {required bool shift}) {
  final k = e.logicalKey;
  final named = <LogicalKeyboardKey, String>{
    LogicalKeyboardKey.arrowUp: 'Up',
    LogicalKeyboardKey.arrowDown: 'Down',
    LogicalKeyboardKey.arrowLeft: 'Left',
    LogicalKeyboardKey.arrowRight: 'Right',
    LogicalKeyboardKey.enter: 'Enter',
    LogicalKeyboardKey.numpadEnter: 'Enter',
    LogicalKeyboardKey.escape: 'Esc',
    LogicalKeyboardKey.home: 'Home',
    LogicalKeyboardKey.end: 'End',
  };
  final n = named[k];
  if (n != null) return n;
  // The character the keyboard layout produced already carries Shift, Caps
  // Lock and AltGr: use it as is, never re-shift it (German Shift+7 is `/`).
  // One exception: with Shift down, a character that is just the key's own
  // unshifted label is a simulated or raw key (a real layout reports the
  // shifted character), so the US shift map applies to it.
  final label = k.keyLabel;
  final typed = e.character;
  final real = typed != null && typed.length == 1 && isPrintableCode(typed);
  if (real && !(shift && typed.toLowerCase() == label.toLowerCase())) {
    return typed;
  }
  var c = real ? typed : (label.length == 1 ? label : null);
  if (c == null) return null;
  if (shift) {
    const shifted = {'/': '?', ';': ':', '[': '{', ']': '}'};
    c = shifted[c] ?? c.toUpperCase();
  } else if (RegExp('[A-Z]').hasMatch(c) && !_capsOn()) {
    c = c.toLowerCase();
  }
  return c;
}

/// Whether the one-character string [c] is printable (not a control).
bool isPrintableCode(String c) {
  final u = c.codeUnitAt(0);
  return u >= 0x20 && u != 0x7f;
}

/// AltGr: Ctrl+Alt (how Windows and Linux report it) with a key event that
/// produced a printable character (German `[ ] { } @ \\`). Such a key is
/// that character, not a Ctrl/Alt chord.
bool isAltGrChar(KeyEvent e, HardwareKeyboard kb) {
  final c = e.character;
  return kb.isControlPressed &&
      kb.isAltPressed &&
      !kb.isMetaPressed &&
      c != null &&
      c.length == 1 &&
      isPrintableCode(c);
}

bool _capsOn() => HardwareKeyboard.instance.lockModesEnabled.contains(
  KeyboardLockMode.capsLock,
);
