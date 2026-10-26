import 'dart:async';
import 'dart:convert';

import 'package:flutter_hbb/mobile/duodesk/duodesk_actions.dart';
import 'package:flutter_hbb/mobile/duodesk/duodesk_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mouse releases satisfy the native string-map input contract', () {
    for (final right in [false, true]) {
      final event = Map<String, String>.from(jsonDecode(duoDeskMouseUp(right)));
      expect(event, {'type': 'up', 'buttons': right ? 'right' : 'left'});
    }
  });

  test('releases a held button even after input permission is lost', () async {
    var allowed = true;
    final mouse = <bool>[];
    final strokes = <DuoDeskStroke>[];
    final modifiers = <Set<DuoDeskModifier>>[];
    var releases = 0;
    final input = DuoDeskInput(
      allowed: () => allowed,
      sendDrag: mouse.add,
      sendClick: (_) {},
      sendStroke: strokes.add,
      syncModifiers: modifiers.add,
      releaseModifiers: () {
        releases++;
      },
      onError: (error, stack) => fail('$error'),
    );
    input.setModifiers({DuoDeskModifier.control});
    await input.drag(true);
    allowed = false;
    await input.reset();
    input.drag(true);
    input.key('x');
    expect(mouse, [true, false]);
    expect(strokes, isEmpty);
    expect(modifiers.last, isEmpty);
    expect(releases, 1);
  });

  test('semantic shortcuts do not inherit sticky modifiers', () async {
    final strokes = <DuoDeskStroke>[];
    final input = DuoDeskInput(
      allowed: () => true,
      sendDrag: (_) {},
      sendClick: (_) {},
      sendStroke: strokes.add,
      syncModifiers: (_) {},
      releaseModifiers: () {},
      onError: (error, stack) => fail('$error'),
    );
    input.setModifiers({DuoDeskModifier.alt});
    input.action(
        DuoDeskAction.paste, DuoDeskHost.linux, DuoDeskProfile.terminal);
    await input.key('VK_TAB');
    expect(strokes.first.key, 'v');
    expect(strokes.first.modifiers,
        {DuoDeskModifier.control, DuoDeskModifier.shift});
    expect(strokes.last.key, 'VK_TAB');
    expect(strokes.last.modifiers, {DuoDeskModifier.alt});
  });
  test('serializes drag release behind an outstanding press', () async {
    final pendingPress = Completer<void>();
    final mouse = <bool>[];
    final input = DuoDeskInput(
      allowed: () => true,
      sendDrag: (down) {
        mouse.add(down);
        return down ? pendingPress.future : Future<void>.value();
      },
      sendClick: (_) {},
      sendStroke: (_) {},
      syncModifiers: (_) {},
      releaseModifiers: () {},
      onError: (error, stack) => fail('$error'),
    );
    input.drag(true);
    final reset = input.reset();
    await Future<void>.delayed(Duration.zero);
    expect(mouse, [true]);
    pendingPress.complete();
    await reset;
    expect(mouse, [true, false]);
  });
}
