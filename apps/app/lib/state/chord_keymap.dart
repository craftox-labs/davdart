import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One key chord: modifiers plus a letter A-Z. Letters match on the physical
/// key (a Mac Option+letter types a special character, so the logical key
/// is useless), and the modifiers must match exactly.
@immutable
class Chord {
  const Chord(
    this.letter, {
    this.ctrl = false,
    this.alt = false,
    this.meta = false,
    this.shift = false,
  });

  /// Lower-case `a` to `z`.
  final String letter;
  final bool ctrl, alt, meta, shift;

  /// The stored form, `ctrl+shift+j`: modifiers in the order ctrl, alt,
  /// meta, shift, then the letter.
  String get id => [
    if (ctrl) 'ctrl',
    if (alt) 'alt',
    if (meta) 'meta',
    if (shift) 'shift',
    letter,
  ].join('+');

  /// The label shown to the user, `Ctrl+Shift+J`, `Cmd+Shift+J`, `Alt+J`.
  String get label => [
    if (ctrl) 'Ctrl',
    if (alt) 'Alt',
    if (meta) 'Cmd',
    if (shift) 'Shift',
    letter.toUpperCase(),
  ].join('+');

  PhysicalKeyboardKey get physical => _physical[letter]!;

  /// Whether [e] with the current modifier state is this chord.
  bool matches(KeyEvent e, HardwareKeyboard kb) =>
      e.physicalKey == physical &&
      kb.isControlPressed == ctrl &&
      kb.isAltPressed == alt &&
      kb.isMetaPressed == meta &&
      kb.isShiftPressed == shift;

  @override
  bool operator ==(Object other) => other is Chord && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => id;

  /// Parses `ctrl+shift+j` (any order, any case; `cmd`, `command`, `super`,
  /// `win` mean meta, `option` means alt, `control` means ctrl). Null unless
  /// there is exactly one letter and at least one of ctrl, alt, meta (a bare
  /// or shift-only letter would take typing).
  static Chord? parse(String s) {
    String? letter;
    var ctrl = false, alt = false, meta = false, shift = false;
    for (final raw in s.toLowerCase().split('+')) {
      final p = raw.trim();
      switch (p) {
        case 'ctrl' || 'control':
          ctrl = true;
        case 'alt' || 'option' || 'opt':
          alt = true;
        case 'meta' || 'cmd' || 'command' || 'super' || 'win':
          meta = true;
        case 'shift':
          shift = true;
        default:
          if (p.length != 1 || !_physical.containsKey(p) || letter != null) {
            return null;
          }
          letter = p;
      }
    }
    if (letter == null || !(ctrl || alt || meta)) return null;
    return Chord(letter, ctrl: ctrl, alt: alt, meta: meta, shift: shift);
  }
}

final _physical = <String, PhysicalKeyboardKey>{
  'a': PhysicalKeyboardKey.keyA,
  'b': PhysicalKeyboardKey.keyB,
  'c': PhysicalKeyboardKey.keyC,
  'd': PhysicalKeyboardKey.keyD,
  'e': PhysicalKeyboardKey.keyE,
  'f': PhysicalKeyboardKey.keyF,
  'g': PhysicalKeyboardKey.keyG,
  'h': PhysicalKeyboardKey.keyH,
  'i': PhysicalKeyboardKey.keyI,
  'j': PhysicalKeyboardKey.keyJ,
  'k': PhysicalKeyboardKey.keyK,
  'l': PhysicalKeyboardKey.keyL,
  'm': PhysicalKeyboardKey.keyM,
  'n': PhysicalKeyboardKey.keyN,
  'o': PhysicalKeyboardKey.keyO,
  'p': PhysicalKeyboardKey.keyP,
  'q': PhysicalKeyboardKey.keyQ,
  'r': PhysicalKeyboardKey.keyR,
  's': PhysicalKeyboardKey.keyS,
  't': PhysicalKeyboardKey.keyT,
  'u': PhysicalKeyboardKey.keyU,
  'v': PhysicalKeyboardKey.keyV,
  'w': PhysicalKeyboardKey.keyW,
  'x': PhysicalKeyboardKey.keyX,
  'y': PhysicalKeyboardKey.keyY,
  'z': PhysicalKeyboardKey.keyZ,
};

/// The global chord layer's key map: action id to chord, the same letters on
/// every platform, the modifiers chosen by platform:
///
/// - native Linux, Windows (and others): Ctrl+Shift+letter
/// - native macOS: Cmd+Shift+letter
/// - web on Linux, Windows: Alt+letter (browsers own most Ctrl+Shift letters)
/// - web on macOS: Ctrl+Alt+letter (Option+letter types characters, so the
///   physical key is matched)
///
/// The letters come from the set browsers leave alone as Alt chords (J K L N
/// P O G Q M R W X Y; no F E V S B T H D, no arrows or digits) minus U and Z
/// (Ctrl+Shift+U is GTK unicode input, Shift+Z is redo in text fields).
/// Letters are key positions: matching uses the physical key, so on a
/// non-QWERTY layout the chord is where the QWERTY letter sits, while the
/// label prints the QWERTY letter. Native macOS swaps Q for T (Tasks):
/// Cmd+Shift+Q logs the user out.
/// Ctrl/Cmd+K (palette), Ctrl/Cmd+Enter (save and leave), Ctrl/Cmd+W and
/// Ctrl/Cmd+S are fixed and never overridden.
///
/// Overrides: the pref `davdart.chords.v1` holds JSON, action id to chord
/// string, `{"go.tasks": "ctrl+alt+t"}`. Unknown ids, unparsable or
/// reserved chords and chords used twice are ignored (the action keeps its
/// default).
class ChordKeymap {
  ChordKeymap({
    TargetPlatform? platform,
    bool? isWeb,
    Map<String, String> overrides = const {},
  }) : platform = platform ?? defaultTargetPlatform,
       isWeb = isWeb ?? debugIsWeb ?? kIsWeb {
    _chords.addAll(_defaults());
    _applyOverrides(overrides);
  }

  /// Reads the overrides from the stored JSON [raw] (null or bad JSON: none).
  factory ChordKeymap.fromPref(
    String? raw, {
    TargetPlatform? platform,
    bool? isWeb,
  }) => ChordKeymap(
    platform: platform,
    isWeb: isWeb,
    overrides: parseOverrides(raw),
  );

  /// Test seam for the web flag.
  static bool? debugIsWeb;

  static const prefKey = 'davdart.chords.v1';

  final TargetPlatform platform;
  final bool isWeb;

  /// The default letters by action id.
  static const letters = <String, String>{
    'focus.left': 'j',
    'focus.right': 'l',
    'tab.previous': 'y',
    'tab.next': 'x',
    'panel.toggle': 'm',
    'peek.toggle': 'p',
    'go.home': 'g',
    'go.notes': 'n',
    'go.tasks': 'q',
    'go.events': 'r',
    'item.new': 'o',
    'palette.open': 'k',
    'edit.leave': 'w',
  };

  /// Letters that differ on native macOS: Cmd+Shift+Q is the system log-out
  /// shortcut, so Tasks takes T there. (Web on macOS uses Ctrl+Alt, which
  /// has no system meaning, and keeps the table above.) Q is not used on
  /// native macOS at all.
  static const macNativeLetters = <String, String>{'go.tasks': 't'};

  /// The default letter of action [id] on this platform. Letters name key
  /// positions as on a QWERTY keyboard (the match is on the physical key).
  String? defaultLetter(String id) =>
      (isMac && !isWeb ? macNativeLetters[id] : null) ?? letters[id];

  /// Chords that other code binds; no action may take them.
  static const reserved = {
    'ctrl+k',
    'meta+k',
    'ctrl+w',
    'meta+w',
    'ctrl+s',
    'meta+s',
  };

  bool get isMac =>
      platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;

  /// The platform's default modifiers (see the class comment).
  Chord defaultFor(String letter) {
    if (isWeb) {
      return isMac
          ? Chord(letter, ctrl: true, alt: true)
          : Chord(letter, alt: true);
    }
    return isMac
        ? Chord(letter, meta: true, shift: true)
        : Chord(letter, ctrl: true, shift: true);
  }

  Map<String, Chord> _defaults() => {
    for (final id in letters.keys) id: defaultFor(defaultLetter(id)!),
  };

  final Map<String, Chord> _chords = {};
  final Map<String, Chord> _defaultChords = {};
  final Set<String> overridden = {};

  void _applyOverrides(Map<String, String> raw) {
    _defaultChords.addAll(_chords);
    final cand = <String, Chord>{};
    for (final e in raw.entries) {
      if (!letters.containsKey(e.key)) continue;
      final c = Chord.parse(e.value);
      if (c == null || reserved.contains(c.id)) continue;
      cand[e.key] = c;
    }
    // Drop overrides until no chord is used twice. An override that collides
    // is dropped (its action falls back to its default); repeat because that
    // can free or take a chord.
    while (true) {
      final eff = {..._defaultChords, ...cand};
      final by = <Chord, List<String>>{};
      for (final e in eff.entries) {
        (by[e.value] ??= []).add(e.key);
      }
      final bad = [
        for (final ids in by.values)
          if (ids.length > 1) ...ids.where(cand.containsKey),
      ];
      if (bad.isEmpty) {
        _chords
          ..clear()
          ..addAll(eff);
        overridden.addAll(cand.keys);
        return;
      }
      bad.forEach(cand.remove);
    }
  }

  /// The chord of action [id], or null if it has none.
  Chord? chordFor(String id) => _chords[id];

  /// All action ids with a chord.
  Iterable<String> get ids => _chords.keys;

  /// The label (`Alt+J`) for the active platform; null if none.
  String? labelFor(String id) => _chords[id]?.label;

  /// The action id whose chord is [e] under the current modifiers.
  String? idFor(KeyEvent e, HardwareKeyboard kb) {
    for (final en in _chords.entries) {
      if (en.value.matches(e, kb)) return en.key;
    }
    return null;
  }

  /// Parses the stored JSON; anything else than an object of strings is
  /// ignored.
  static Map<String, String> parseOverrides(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return const {};
      return {
        for (final e in j.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      };
    } catch (_) {
      return const {};
    }
  }

  /// The JSON to store for [overrides].
  static String formatOverrides(Map<String, String> overrides) =>
      jsonEncode(overrides);
}
