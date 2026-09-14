// Every controller that writes state after an await orders its answers.
//
// WHY THIS FILE EXISTS. Seven controllers applied whatever response arrived,
// whenever it arrived. One of them lost a customer's confirmed pickup time on
// the Android emulator (KI-041); the audit that followed found the same fault in
// the cart, the checkout quote, the route, the session, the journeys and the
// saved addresses (KI-042 to KI-044). Each was fixed the same way: a ticket
// taken on the way out, an answer applied only if nothing newer has been issued
// since. Seven hand-written copies of one rule, and nothing that says the eighth
// controller has to follow it. Module 18 adds an eighth. This says so.
//
// IT READS SOURCE, NOT BEHAVIOUR. Dart has no run-time reflection over private
// fields, and a behavioural test would need a fake and a race for every
// controller — which is what the seven `*_ordering_test.dart` files are, and
// exactly the kind of test nobody writes for the eighth. So this strips comments
// and looks for the shape: a controller that both awaits and assigns `state`
// must also compare a ticket against its counter. The COMPARISON, not the
// declaration — a counter that is declared and never checked is the fault with a
// field added.
//
// THE ALLOWLIST ROTS IN BOTH DIRECTIONS, so it is checked in both. A name that
// is no longer on disk fails, because an entry for a file that was renamed
// covers nothing. A name whose file has since gained a guard fails too, because
// the reason recorded beside it is no longer true and a stale exemption is how a
// future edit that removes the guard goes unnoticed.
//
// THE CONTROLS ARE ON STRINGS, deliberately: the scanner is a pure function
// over text, and the snippets below prove it rejects what it should reject
// before it is trusted to accept the real files. A guard that has never been
// seen to fail has not been seen to work.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What the scanner concluded about one file.
enum OrderingVerdict {
  /// No `state =` after an `await` — nothing here can arrive out of order.
  notAnAsyncWriter,

  /// Awaits, writes state, and compares a ticket against its counter.
  guarded,

  /// Awaits and writes state with no ordering check at all.
  unguarded,
}

/// Comment-stripped source, so a guard mentioned in prose does not count and a
/// guard commented out does not either.
String _stripComments(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((String line) => line.replaceFirst(RegExp(r'\s*//.*'), ''))
    .join('\n');

/// The verdict for a whole file: the worst verdict of any class in it.
///
/// Scoped per class, not per file, and the reason is on disk: `providers.dart`
/// holds two synchronous notifiers that assign `state` and, forty lines away,
/// an API client whose token reader awaits storage. Read as one text that is an
/// unguarded async writer; read as classes it is nothing of the kind. The first
/// draft of this scanner flagged it, which is the false positive the control
/// below now pins.
OrderingVerdict classify(String source) {
  final String code = _stripComments(source);

  OrderingVerdict worst = OrderingVerdict.notAnAsyncWriter;

  for (final String body in _classBodies(code)) {
    final OrderingVerdict verdict = _classifyClass(body);

    if (verdict == OrderingVerdict.unguarded) return verdict;
    if (verdict == OrderingVerdict.guarded) worst = verdict;
  }

  return worst;
}

/// Each `class` body, from its opening brace to the matching close.
///
/// Brace-matched rather than "from this `class` to the next", because the
/// first draft did the latter and the LAST class in a file swallowed every
/// provider and helper declared after it — which is how a synchronous notifier
/// at the top of `providers.dart` was blamed for a token reader that awaits at
/// the bottom. Top-level code is not a class and is not scanned.
Iterable<String> _classBodies(String code) sync* {
  final Iterable<RegExpMatch> heads = RegExp(
    r'^(?:abstract\s+|final\s+|base\s+|sealed\s+)*class\s[^{]*\{',
    multiLine: true,
  ).allMatches(code);

  for (final RegExpMatch head in heads) {
    int depth = 1;
    int i = head.end;

    while (i < code.length && depth > 0) {
      final String c = code[i];
      if (c == '{') depth++;
      if (c == '}') depth--;
      i++;
    }

    yield code.substring(head.start, i);
  }
}

OrderingVerdict _classifyClass(String body) {
  final bool writesState = RegExp(r'\bstate\s*=[^=]').hasMatch(body);
  final bool awaits = RegExp(r'\bawait\b').hasMatch(body);

  if (!writesState || !awaits) return OrderingVerdict.notAnAsyncWriter;

  // The comparison is what counts. `int _generation = 0;` on its own is a
  // field; `ticket != _generation` is a rule.
  final bool compares = RegExp(
    r'!=\s*_(generation|sequence|[a-zA-Z]+Generation)\b',
  ).hasMatch(body);

  return compares ? OrderingVerdict.guarded : OrderingVerdict.unguarded;
}

/// Controllers that write state after an await and are deliberately not
/// ticketed. Every entry needs a reason a reader can check against the file.
const Map<String, String> allowedUnguarded = <String, String>{
  'order_controller.dart':
      'place() and pay() are gated on isBusy, so neither can overlap itself or '
      'the other; load() has no caller in the app. A guard on code nothing calls '
      'is a guard nobody maintains — recorded in KI-043 as unreachable.',
  'trip_planner_controller.dart':
      'The only write after an await is clearing isCreating in a finally block; '
      'the plan itself is written synchronously before the request goes out. A '
      'late answer can only clear a flag, never a place the customer chose.',
  'current_location_controller.dart':
      'resolve() is single-flight by construction: while it runs the picker '
      'renders the Locating row with onTap: null, so nothing can start a second '
      'one, and reset() has no caller in the app. There is no second writer for '
      'an older answer to land on top of.',
};

void main() {
  final Directory stateDir = Directory('lib/shared/state');

  group('the scanner', () {
    test('flags a controller that awaits and writes state unguarded', () {
      const String snippet = '''
class Thing extends Notifier<int> {
  Future<void> load() async {
    final int answer = await repo.read();
    state = answer;
  }
}''';
      expect(classify(snippet), OrderingVerdict.unguarded);
    });

    test('accepts one that compares a ticket before writing', () {
      const String snippet = '''
class Thing extends Notifier<int> {
  int _generation = 0;
  Future<void> load() async {
    final int ticket = ++_generation;
    final int answer = await repo.read();
    if (ticket != _generation) return;
    state = answer;
  }
}''';
      expect(classify(snippet), OrderingVerdict.guarded);
    });

    test('a counter that is declared but never compared is not a guard', () {
      // The fault with a field added. This is the control that proves the
      // scanner reads the comparison and not the declaration.
      const String snippet = '''
class Thing extends Notifier<int> {
  int _generation = 0;
  Future<void> load() async {
    _generation++;
    final int answer = await repo.read();
    state = answer;
  }
}''';
      expect(classify(snippet), OrderingVerdict.unguarded);
    });

    test('a guard that only exists in a comment is not a guard', () {
      const String snippet = '''
class Thing extends Notifier<int> {
  Future<void> load() async {
    final int answer = await repo.read();
    // if (ticket != _generation) return;
    /* if (ticket != _generation) return; */
    state = answer;
  }
}''';
      expect(classify(snippet), OrderingVerdict.unguarded);
    });

    test('a controller with no await is out of scope', () {
      const String snippet = '''
class Thing extends Notifier<int> {
  void set(int value) {
    state = value;
  }
}''';
      expect(classify(snippet), OrderingVerdict.notAnAsyncWriter);
    });

    test('an await in one class does not indict a state write in another', () {
      // The false positive the first draft produced on providers.dart: two
      // synchronous notifiers and, elsewhere in the file, a function that
      // awaits. Neither class is an async writer, so the file is not one.
      const String snippet = '''
class Persona extends Notifier<int> {
  void select(int value) => state = value;
}

final client = Provider((ref) => Client(
  tokenReader: () async => (await store.read())?.token,
));''';
      expect(classify(snippet), OrderingVerdict.notAnAsyncWriter);
    });

    test('one unguarded class fails a file that also holds a guarded one', () {
      const String snippet = '''
class Good extends Notifier<int> {
  int _generation = 0;
  Future<void> load() async {
    final int ticket = ++_generation;
    final int answer = await repo.read();
    if (ticket != _generation) return;
    state = answer;
  }
}

class Bad extends Notifier<int> {
  Future<void> load() async {
    final int answer = await repo.read();
    state = answer;
  }
}''';
      expect(classify(snippet), OrderingVerdict.unguarded);
    });

    test('an equality test is not mistaken for an assignment', () {
      const String snippet = '''
class Thing extends Notifier<int> {
  Future<bool> same() async {
    final int answer = await repo.read();
    return state == answer;
  }
}''';
      expect(classify(snippet), OrderingVerdict.notAnAsyncWriter);
    });
  });

  group('the controllers', () {
    late Map<String, OrderingVerdict> verdicts;

    setUpAll(() {
      verdicts = <String, OrderingVerdict>{
        for (final FileSystemEntity entity in stateDir.listSync())
          if (entity is File && entity.path.endsWith('.dart'))
            entity.uri.pathSegments.last: classify(entity.readAsStringSync()),
      };
    });

    test('the scan found the controllers it is meant to cover', () {
      // A glob that matches nothing passes every "all files are guarded"
      // assertion for free. Anchored on files that are known to be guarded, so
      // a move of the directory fails here rather than passing everywhere.
      expect(verdicts['pickup_controller.dart'], OrderingVerdict.guarded);
      expect(verdicts['cart_controller.dart'], OrderingVerdict.guarded);
      expect(verdicts['auth_controller.dart'], OrderingVerdict.guarded);
      expect(
        verdicts.values.where(
          (OrderingVerdict v) => v == OrderingVerdict.guarded,
        ),
        hasLength(greaterThanOrEqualTo(12)),
      );
    });

    test('every controller that writes state after an await is guarded', () {
      final List<String> unguarded = <String>[
        for (final MapEntry<String, OrderingVerdict> e in verdicts.entries)
          if (e.value == OrderingVerdict.unguarded &&
              !allowedUnguarded.containsKey(e.key))
            e.key,
      ]..sort();

      expect(
        unguarded,
        isEmpty,
        reason:
            'These controllers assign `state` after an `await` and never '
            'compare a ticket against a counter, so an older answer can land '
            'on top of a newer one. Take a ticket on the way out and apply the '
            'answer only if nothing newer has been issued — see '
            'PickupController for the shape and KI-041 for why. If the file '
            'genuinely cannot race, add it to allowedUnguarded with a reason '
            'the next reader can check.',
      );
    });

    test('every allowlist entry is still true', () {
      for (final MapEntry<String, String> entry in allowedUnguarded.entries) {
        expect(
          verdicts.containsKey(entry.key),
          isTrue,
          reason:
              '${entry.key} is allowlisted but not on disk. An exemption for a '
              'file that was renamed or removed covers nothing; delete it.',
        );
        expect(
          verdicts[entry.key],
          OrderingVerdict.unguarded,
          reason:
              '${entry.key} is allowlisted as unguarded but no longer is. The '
              'reason recorded beside it is stale; remove the entry so a later '
              'edit that drops the guard is caught.',
        );
      }
    });
  });
}
