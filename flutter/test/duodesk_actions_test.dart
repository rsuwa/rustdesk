import 'package:flutter_hbb/mobile/duodesk/duodesk_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paste selects the host and work profile shortcut', () {
    for (final host in DuoDeskHost.values) {
      for (final profile in DuoDeskProfile.values) {
        final stroke =
            duoDeskShortcut(DuoDeskAction.paste, host, profile).single;
        expect(stroke.key, 'v');
        expect(
            stroke.modifiers,
            host == DuoDeskHost.macOS
                ? {DuoDeskModifier.command}
                : host == DuoDeskHost.linux &&
                        profile == DuoDeskProfile.terminal
                    ? {DuoDeskModifier.control, DuoDeskModifier.shift}
                    : {DuoDeskModifier.control});
      }
    }
  });

  test('terminal interrupt and tmux sequences keep Control on every host', () {
    for (final host in DuoDeskHost.values) {
      final interrupt = duoDeskShortcut(
              DuoDeskAction.interrupt, host, DuoDeskProfile.terminal)
          .single;
      expect(interrupt.key, 'c');
      expect(interrupt.modifiers, {DuoDeskModifier.control});
      final next = duoDeskShortcut(
          DuoDeskAction.tmuxNext, host, DuoDeskProfile.terminal);
      expect(next.map((stroke) => stroke.key), ['b', 'n']);
      expect(next.first.modifiers, {DuoDeskModifier.control});
      expect(next.last.modifiers, isEmpty);
    }
  });
}
