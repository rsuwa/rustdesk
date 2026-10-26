import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'duodesk_actions.dart';

enum _DeskLayout { automatic, desk, canvas, compact }

class DuoDeskWorkspace extends StatefulWidget {
  const DuoDeskWorkspace({
    super.key,
    required this.viewport,
    required this.onViewportChanged,
    required this.onMove,
    required this.onScroll,
    required this.onLeftClick,
    required this.onRightClick,
    required this.onKeyboard,
    required this.onResetInput,
    required this.onDrag,
    required this.onKey,
    required this.onAction,
    required this.onModifiersChanged,
    this.enabled = true,
    this.isMac = false,
  });

  final Widget viewport;
  final ValueChanged<Size> onViewportChanged;
  final ValueChanged<Offset> onMove;
  final ValueChanged<Offset> onScroll;
  final VoidCallback onLeftClick;
  final VoidCallback onRightClick;
  final VoidCallback onKeyboard;
  final VoidCallback onResetInput;
  final ValueChanged<bool> onDrag;
  final ValueChanged<String> onKey;
  final void Function(DuoDeskAction, DuoDeskProfile) onAction;
  final ValueChanged<Set<DuoDeskModifier>> onModifiersChanged;
  final bool enabled;
  final bool isMac;

  @override
  State<DuoDeskWorkspace> createState() => _DuoDeskWorkspaceState();
}

class _DuoDeskWorkspaceState extends State<DuoDeskWorkspace>
    with WidgetsBindingObserver {
  static const _surface = Color(0xff171c24);
  static const _padColor = Color(0xff222b35);
  static const _accent = Color(0xff8bd6cc);
  DuoDeskProfile _profile = DuoDeskProfile.pointer;
  _DeskLayout _layout = _DeskLayout.automatic;
  bool _expanded = false;
  bool _dragging = false;
  bool _dragLocked = false;
  double _sensitivity = 1;
  Offset _longPressPosition = Offset.zero;
  final _modifiers = <DuoDeskModifier>{};
  Size? _viewportSize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _resetInput() {
    if (_dragging) widget.onDrag(false);
    _dragging = false;
    _dragLocked = false;
    if (_modifiers.isNotEmpty) {
      _modifiers.clear();
      widget.onModifiersChanged({});
    }
    widget.onResetInput();
  }

  @override
  void didUpdateWidget(DuoDeskWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) _resetInput();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      setState(_resetInput);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resetInput();
    super.dispose();
  }

  void _reportViewport(Size size) {
    if (_viewportSize == size || size.isEmpty) return;
    final wasSized = _viewportSize != null;
    _viewportSize = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _viewportSize != size) return;
      if (wasSized) setState(_resetInput);
      widget.onViewportChanged(size);
    });
  }

  void _setProfile(DuoDeskProfile profile) {
    if (_profile == profile) return;
    setState(() {
      _resetInput();
      _profile = profile;
    });
  }

  Widget _button(String label, VoidCallback onPressed,
      {bool selected = false, Key? key}) {
    return TextButton(
      key: key,
      onPressed: widget.enabled ? onPressed : null,
      style: TextButton.styleFrom(
        foregroundColor: selected ? const Color(0xff102521) : Colors.white,
        backgroundColor: selected ? _accent : Colors.transparent,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label),
    );
  }

  Widget _icon(IconData icon, String tooltip, VoidCallback onPressed,
      {bool selected = false, Key? key}) {
    return IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: widget.enabled ? onPressed : null,
      color: selected ? _accent : Colors.white,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      icon: Icon(icon),
    );
  }

  Widget _horizontal(List<Widget> children) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: children),
      );

  Widget _header(_DeskLayout layout) {
    return SizedBox(
      height: 48,
      child: Row(children: [
        Expanded(
          child: _horizontal([
            _button('Pointer', () => _setProfile(DuoDeskProfile.pointer),
                selected: _profile == DuoDeskProfile.pointer),
            _button('Terminal', () => _setProfile(DuoDeskProfile.terminal),
                selected: _profile == DuoDeskProfile.terminal),
          ]),
        ),
        _icon(Icons.keyboard_outlined, 'キーボード', widget.onKeyboard,
            key: const ValueKey('duodesk-keyboard')),
        PopupMenuButton<_DeskLayout>(
          tooltip: 'レイアウト',
          icon: const Icon(Icons.view_quilt_outlined, color: Colors.white),
          initialValue: _layout,
          onSelected: (value) => setState(() {
            _resetInput();
            _layout = value;
          }),
          itemBuilder: (_) => [
            for (final entry in const {
              _DeskLayout.automatic: '自動',
              _DeskLayout.desk: 'Desk',
              _DeskLayout.canvas: 'Canvas',
              _DeskLayout.compact: 'Compact',
            }.entries)
              PopupMenuItem(value: entry.key, child: Text(entry.value)),
          ],
        ),
        if (layout == _DeskLayout.canvas)
          IconButton(
            tooltip: _expanded ? '操作デッキを閉じる' : '操作デッキを開く',
            icon: Icon(_expanded ? Icons.expand_more : Icons.expand_less,
                color: Colors.white),
            onPressed: () => setState(() {
              _resetInput();
              _expanded = !_expanded;
            }),
          ),
      ]),
    );
  }

  Widget _modifierRow() => _horizontal([
        for (final entry in {
          DuoDeskModifier.control: 'Ctrl',
          DuoDeskModifier.alt: 'Alt',
          DuoDeskModifier.shift: 'Shift',
          DuoDeskModifier.command: widget.isMac ? 'Command' : 'Super',
        }.entries)
          _button(entry.value, () {
            setState(() {
              if (!_modifiers.add(entry.key)) _modifiers.remove(entry.key);
              widget.onModifiersChanged(Set.of(_modifiers));
            });
          }, selected: _modifiers.contains(entry.key)),
        _button('コピー', () => widget.onAction(DuoDeskAction.copy, _profile)),
        _button('貼り付け', () => widget.onAction(DuoDeskAction.paste, _profile)),
      ]);

  Widget _terminalKeys() => _horizontal([
        for (final entry in const {
          'Esc': 'VK_ESCAPE',
          'Tab': 'VK_TAB',
          'Enter': 'VK_ENTER',
          '←': 'VK_LEFT',
          '↑': 'VK_UP',
          '↓': 'VK_DOWN',
          '→': 'VK_RIGHT',
        }.entries)
          _button(entry.key, () => widget.onKey(entry.value)),
      ]);

  Widget _terminalActions() => _horizontal([
        for (final entry in const {
          'Ctrl+C': DuoDeskAction.interrupt,
          'Ctrl+R': DuoDeskAction.search,
          'Ctrl+A': DuoDeskAction.lineStart,
          'Ctrl+E': DuoDeskAction.lineEnd,
          'tmux prefix': DuoDeskAction.tmuxPrefix,
          'tmux 次': DuoDeskAction.tmuxNext,
          'tmux 前': DuoDeskAction.tmuxPrevious,
        }.entries)
          _button(entry.key, () => widget.onAction(entry.value, _profile)),
      ]);

  void _startDrag() {
    if (!widget.enabled || _dragging) return;
    setState(() => _dragging = true);
    widget.onDrag(true);
  }

  void _endDrag() {
    if (!_dragging || _dragLocked) return;
    setState(() => _dragging = false);
    widget.onDrag(false);
  }

  void _click({bool right = false}) {
    if (_dragLocked) {
      setState(() {
        _dragLocked = false;
        _dragging = false;
      });
      widget.onDrag(false);
      if (!right) return;
    }
    if (right) {
      widget.onRightClick();
    } else {
      widget.onLeftClick();
    }
  }

  Widget _trackpad() {
    return Listener(
      onPointerCancel: (_) => setState(_resetInput),
      child: GestureDetector(
        key: const ValueKey('duodesk-trackpad'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? () => _click() : null,
        onSecondaryTap: widget.enabled ? () => _click(right: true) : null,
        onScaleUpdate: widget.enabled
            ? (details) {
                if (details.pointerCount >= 2) {
                  widget.onScroll(details.focalPointDelta);
                } else {
                  widget.onMove(details.focalPointDelta * _sensitivity);
                }
              }
            : null,
        onLongPressStart: widget.enabled
            ? (details) {
                _longPressPosition = details.localPosition;
                _startDrag();
              }
            : null,
        onLongPressMoveUpdate: widget.enabled
            ? (details) {
                widget.onMove((details.localPosition - _longPressPosition) *
                    _sensitivity);
                _longPressPosition = details.localPosition;
              }
            : null,
        onLongPressEnd: (_) => _endDrag(),
        onLongPressCancel: _endDrag,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _padColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: _dragging ? _accent : const Color(0xff394551),
                width: _dragging ? 2 : 1),
          ),
          alignment: Alignment.center,
          child: Text(
            _dragging ? 'ドラッグ中' : '1本指で移動 · 2本指でスクロール',
            style: TextStyle(
                color: widget.enabled ? Colors.white70 : Colors.white30,
                fontSize: 12),
          ),
        ),
      ),
    );
  }

  Widget _pointerControls() => Row(children: [
        _button('左クリック', () => _click()),
        _button('右クリック', () => _click(right: true),
            key: const ValueKey('duodesk-right-click')),
        _icon(Icons.lock_outline, 'ドラッグロック', () {
          if (_dragLocked) {
            setState(() {
              _dragLocked = false;
              _dragging = false;
            });
            widget.onDrag(false);
          } else {
            _startDrag();
            setState(() => _dragLocked = true);
          }
        }, selected: _dragLocked),
        Expanded(
          child: Slider(
            value: _sensitivity,
            min: 0.5,
            max: 2,
            divisions: 6,
            label: '感度 ${_sensitivity.toStringAsFixed(2)}',
            activeColor: _accent,
            onChanged: widget.enabled
                ? (value) => setState(() => _sensitivity = value)
                : null,
          ),
        ),
      ]);

  Widget _deck(_DeskLayout layout) {
    final terminal = _profile == DuoDeskProfile.terminal;
    return Material(
      color: _surface,
      child: Column(children: [
        _header(layout),
        if (layout != _DeskLayout.canvas || _expanded)
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final toolsHeight = math.min(terminal ? 132.0 : 44.0,
                  math.max(44.0, constraints.maxHeight * 0.48));
              return Column(children: [
                SizedBox(
                  height: toolsHeight,
                  child: SingleChildScrollView(
                    child: Column(children: [
                      _modifierRow(),
                      if (terminal) _terminalKeys(),
                      if (terminal) _terminalActions(),
                    ]),
                  ),
                ),
                Expanded(child: _trackpad()),
                _pointerControls(),
              ]);
            }),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final layout = _layout != _DeskLayout.automatic
          ? _layout
          : constraints.maxHeight < 420
              ? _DeskLayout.canvas
              : constraints.maxWidth < 600
                  ? _DeskLayout.compact
                  : _DeskLayout.desk;
      final canvas = layout == _DeskLayout.canvas;
      final deckHeight = canvas && !_expanded
          ? 48.0
          : math.min(constraints.maxHeight * (canvas ? 0.8 : 0.48),
              layout == _DeskLayout.desk ? 420.0 : 360.0);
      return Stack(children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          bottom: canvas ? 0 : deckHeight,
          child: ClipRect(
            child: LayoutBuilder(builder: (context, viewportConstraints) {
              _reportViewport(viewportConstraints.biggest);
              return widget.viewport;
            }),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: deckHeight,
          child: _deck(layout),
        ),
      ]);
    });
  }
}
