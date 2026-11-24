/// The fixed board status set, in board order. Every Space uses it.
const allowedStatuses = [
  'backlog',
  'todo',
  'doing',
  'blocked',
  'review',
  'done',
  'canceled',
];

/// Words accepted as another spelling of an allowed status.
const statusAliases = {
  'in_progress': 'doing',
  'in-progress': 'doing',
  'cancelled': 'canceled',
  'duplicate': 'canceled',
  'wontfix': 'canceled',
  'draft': 'backlog',
  'in_review': 'review',
  'in-review': 'review',
  'ready_for_review': 'review',
  'to_review': 'review',
};

/// The allowed status for [word] (trimmed, lower-cased, aliases resolved), or
/// null when it is not one of them.
String? canonicalStatus(String word) {
  final w = word.trim().toLowerCase();
  if (allowedStatuses.contains(w)) return w;
  return statusAliases[w];
}

/// The note priority words, highest first, with the task priority each maps to
/// (RFC 5545: 1-4 high, 5 medium, 6-9 low).
const notePriorities = {'high': 1, 'medium': 5, 'low': 9};

/// The note priority word for a task-style number (1-4 high, 5 medium, 6-9
/// low), or null for none (null or 0).
String? priorityWordOf(int? p) => p == null || p <= 0
    ? null
    : p <= 4
        ? 'high'
        : p == 5
            ? 'medium'
            : 'low';
