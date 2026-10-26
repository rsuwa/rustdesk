import 'dart:async';
import 'dart:convert';

import 'duodesk_actions.dart';

String duoDeskMouseUp(bool right) => jsonEncode(<String, String>{
      'type': 'up',
      'buttons': right ? 'right' : 'left',
    });

class DuoDeskInput {
  DuoDeskInput({
    required this.allowed,
    required this.sendDrag,
    required this.sendClick,
    required this.sendStroke,
    required this.syncModifiers,
    required this.releaseModifiers,
    required this.onError,
  });

  final bool Function() allowed;
  final FutureOr<void> Function(bool) sendDrag;
  final FutureOr<void> Function(bool) sendClick;
  final FutureOr<void> Function(DuoDeskStroke) sendStroke;
  final void Function(Set<DuoDeskModifier>) syncModifiers;
  final FutureOr<void> Function() releaseModifiers;
  final void Function(Object, StackTrace) onError;
  bool _dragging = false;
  Set<DuoDeskModifier> _modifiers = {};
  Future<void> _pending = Future.value();

  Future<void> _enqueue(FutureOr<void> Function() operation) {
    _pending = _pending.then((_) async {
      try {
        await operation();
      } catch (error, stack) {
        onError(error, stack);
      }
    });
    return _pending;
  }

  Future<void> drag(bool down) {
    if (down && !allowed()) return _pending;
    if (_dragging == down) return _pending;
    _dragging = down;
    return _enqueue(() => sendDrag(down));
  }

  void setModifiers(Set<DuoDeskModifier> modifiers) {
    if (!allowed()) return;
    _modifiers = Set.of(modifiers);
    syncModifiers(_modifiers);
  }

  Future<void> click(bool right) {
    if (!allowed()) return _pending;
    return _enqueue(() => sendClick(right));
  }

  Future<void> key(String key) {
    if (!allowed()) return _pending;
    final stroke = DuoDeskStroke(key, Set.of(_modifiers));
    return _enqueue(() async {
      if (allowed()) await sendStroke(stroke);
    });
  }

  Future<void> action(
      DuoDeskAction action, DuoDeskHost host, DuoDeskProfile profile) {
    if (!allowed()) return _pending;
    return _enqueue(() async {
      for (final stroke in duoDeskShortcut(action, host, profile)) {
        if (!allowed()) return;
        await sendStroke(stroke);
      }
    });
  }

  Future<void> reset() {
    drag(false);
    _modifiers = {};
    syncModifiers(_modifiers);
    return _enqueue(releaseModifiers);
  }
}
