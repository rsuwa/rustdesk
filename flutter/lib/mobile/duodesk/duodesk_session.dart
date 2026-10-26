import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';

import '../../consts.dart';
import '../../models/input_model.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import 'duodesk_actions.dart';
import 'duodesk_input.dart';

class DuoDeskSessionInput {
  DuoDeskSessionInput(this.ffi);

  final FFI ffi;
  bool _disposed = false;

  bool get enabled =>
      !_disposed &&
      !ffi.closed &&
      ffi.ffiModel.pi.isSet.value &&
      !ffi.ffiModel.waitForFirstImage.value &&
      ffi.inputModel.keyboardPerm &&
      !ffi.inputModel.isViewOnly;

  late final input = DuoDeskInput(
    allowed: () => enabled,
    sendDrag: (down) async {
      if (_disposed) return;
      if (down) {
        if (enabled) await ffi.inputModel.tapDown(MouseButtons.left);
      } else {
        // A matching release must also pass after permission was revoked.
        await bind.sessionSendMouse(
            sessionId: ffi.sessionId, msg: duoDeskMouseUp(false));
      }
    },
    sendStroke: _sendStroke,
    sendClick: (right) async {
      if (!enabled) return;
      final button = right ? MouseButtons.right : MouseButtons.left;
      await ffi.inputModel.tapDown(button);
      if (!_disposed) {
        await bind.sessionSendMouse(
          sessionId: ffi.sessionId,
          msg: duoDeskMouseUp(right),
        );
      }
    },
    syncModifiers: _syncModifiers,
    releaseModifiers: _releaseModifiers,
    onError: (error, stack) =>
        debugPrint('DuoDesk input failed: $error\n$stack'),
  );

  void _syncModifiers(Set<DuoDeskModifier> modifiers) {
    if (_disposed) return;
    final model = ffi.inputModel;
    model.ctrl = modifiers.contains(DuoDeskModifier.control);
    model.alt = modifiers.contains(DuoDeskModifier.alt);
    model.shift = modifiers.contains(DuoDeskModifier.shift);
    model.command = modifiers.contains(DuoDeskModifier.command);
  }

  Future<void> _releaseModifiers() async {
    for (final name in ['VK_CONTROL', 'VK_MENU', 'VK_SHIFT', 'Meta']) {
      if (_disposed) return;
      await bind.sessionInputKey(
        sessionId: ffi.sessionId,
        name: name,
        down: false,
        press: false,
        alt: false,
        ctrl: false,
        shift: false,
        command: false,
      );
    }
  }

  void dispose() {
    _syncModifiers({});
    _disposed = true;
  }

  Future<void> _sendStroke(DuoDeskStroke stroke) async {
    if (!enabled) return;
    try {
      await bind.sessionInputKey(
        sessionId: ffi.sessionId,
        name: stroke.key,
        down: false,
        press: true,
        alt: stroke.modifiers.contains(DuoDeskModifier.alt),
        ctrl: stroke.modifiers.contains(DuoDeskModifier.control),
        shift: stroke.modifiers.contains(DuoDeskModifier.shift),
        command: stroke.modifiers.contains(DuoDeskModifier.command),
      );
    } finally {
      await _releaseModifiers();
    }
  }

  void move(Offset delta) {
    if (enabled) ffi.cursorModel.updatePan(delta, Offset.zero, false);
  }

  void click(MouseButtons button) {
    input.click(button == MouseButtons.right);
  }

  void scroll(Offset delta) {
    if (!enabled) return;
    // Reuse RustDesk's two-axis trackpad scaling without starting a fling.
    ffi.inputModel.onPointerPanZoomStart(const PointerPanZoomStartEvent());
    ffi.inputModel
        .onPointerPanZoomUpdate(PointerPanZoomUpdateEvent(panDelta: delta));
  }

  void action(DuoDeskAction action, DuoDeskProfile profile) {
    if (action == DuoDeskAction.paste && !ffi.inputModel.keyboardInputAllowed) {
      return;
    }
    final host = ffi.ffiModel.pi.platform == kPeerPlatformMacOS
        ? DuoDeskHost.macOS
        : ffi.ffiModel.pi.platform == kPeerPlatformLinux
            ? DuoDeskHost.linux
            : DuoDeskHost.windows;
    input.action(action, host, profile);
  }
}
