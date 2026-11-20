/// The bindings of the Vim editor, for the help overlay (group 'Vim
/// editing'). Static: the engine's keys are fixed, not read from the action
/// registry. Keep in step with [VimEngine].
const vimHelpGroup = 'Vim editing';

const vimHelpRows = <(String, String)>[
  ('Esc', 'To Normal (does nothing in Normal)'),
  ('i a I A o O', 'Insert: here, after, line start/end, new line'),
  ('h j k l', 'Move; counts repeat: 5j'),
  ('w b e W B E', 'Word motions'),
  ('0 ^ \$ gg G', 'Line start/end, first/last line (5G)'),
  ('f F t T ; ,', 'Find a character in the line'),
  ('{ } %', 'Paragraph, matching bracket'),
  ('d c y + motion', 'dw, c\$, y2j, di(, ciw, yip'),
  ('dd cc yy D C Y', 'Whole lines, to line end'),
  ('x X s S r J ~', 'Delete, change, replace, join, case'),
  ('p P', 'Put after / before'),
  ('u Ctrl+r .', 'Undo, redo, repeat'),
  ('v V', 'Visual: characters, lines (o swaps ends)'),
  ('/ ? n N', 'Search (regex)'),
  (':w :wq ZZ', 'Save; save and leave'),
  (':q :q! :5', 'Leave; discard; go to line'),
  ('Space + key', 'App keys (Space g t); Space Space: palette'),
];
