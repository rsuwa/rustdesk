import 'package:flutter/material.dart';
import 'package:flutter_hbb/mobile/duodesk/duodesk_actions.dart';
import 'package:flutter_hbb/mobile/duodesk/duodesk_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

class _Viewport extends StatefulWidget {
  const _Viewport();

  @override
  State<_Viewport> createState() => _ViewportState();
}

class _ViewportState extends State<_Viewport> {
  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black);
}

void main() {
  testWidgets('resizes the viewport without replacing its state or overflowing',
      (tester) async {
    final sizes = <Size>[];
    Widget app() => MaterialApp(
          home: Scaffold(
            body: DuoDeskWorkspace(
              viewport: const _Viewport(),
              onViewportChanged: sizes.add,
              onMove: (_) {},
              onScroll: (_) {},
              onLeftClick: () {},
              onRightClick: () {},
              onKeyboard: () {},
              onResetInput: () {},
              onDrag: (_) {},
              onKey: (_) {},
              onAction: (_, __) {},
              onModifiersChanged: (_) {},
            ),
          ),
        );
    await tester.binding.setSurfaceSize(const Size(760, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app());
    await tester.pump();
    final state = tester.state(find.byType(_Viewport));
    expect(sizes.last.height, lessThan(900));
    for (final size in [const Size(390, 700), const Size(820, 320)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.state(find.byType(_Viewport)), same(state));
      expect(sizes.last.width, size.width);
      expect(sizes.last.height, greaterThan(0));
    }
  });

  testWidgets('trackpad sends movement, clicks and two-axis scroll',
      (tester) async {
    final moves = <Offset>[];
    final scrolls = <Offset>[];
    var leftClicks = 0;
    var rightClicks = 0;
    await tester.binding.setSurfaceSize(const Size(760, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DuoDeskWorkspace(
          viewport: const SizedBox(),
          onViewportChanged: (_) {},
          onMove: moves.add,
          onScroll: scrolls.add,
          onLeftClick: () => leftClicks++,
          onRightClick: () => rightClicks++,
          onKeyboard: () {},
          onResetInput: () {},
          onDrag: (_) {},
          onKey: (_) {},
          onAction: (_, __) {},
          onModifiersChanged: (_) {},
        ),
      ),
    ));
    final pad = find.byKey(const ValueKey('duodesk-trackpad'));
    await tester.tap(pad);
    await tester.pump();
    expect(leftClicks, 1);
    await tester.tap(find.byKey(const ValueKey('duodesk-right-click')));
    expect(rightClicks, 1);
    await tester.drag(pad, const Offset(80, 50));
    expect(moves, isNotEmpty);
    expect(moves.fold(Offset.zero, (sum, delta) => sum + delta).dx,
        greaterThan(0));
    final center = tester.getCenter(pad);
    final first =
        await tester.startGesture(center - const Offset(30, 0), pointer: 1);
    final second =
        await tester.startGesture(center + const Offset(30, 0), pointer: 2);
    await first.moveBy(const Offset(35, 40));
    await second.moveBy(const Offset(35, 40));
    await tester.pump();
    await first.moveBy(const Offset(25, 20));
    await second.moveBy(const Offset(25, 20));
    await first.up();
    await second.up();
    expect(scrolls, isNotEmpty);
    final scroll = scrolls.fold(Offset.zero, (sum, delta) => sum + delta);
    expect(scroll.dx, greaterThan(0));
    expect(scroll.dy, greaterThan(0));
  });

  testWidgets('cancels drag and clears modifiers when changing profile',
      (tester) async {
    final drag = <bool>[];
    final modifiers = <Set<DuoDeskModifier>>[];
    final actions = <(DuoDeskAction, DuoDeskProfile)>[];
    var resets = 0;
    await tester.binding.setSurfaceSize(const Size(760, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DuoDeskWorkspace(
          viewport: const SizedBox(),
          onViewportChanged: (_) {},
          onMove: (_) {},
          onScroll: (_) {},
          onLeftClick: () {},
          onRightClick: () {},
          onKeyboard: () {},
          onResetInput: () => resets++,
          onDrag: drag.add,
          onKey: (_) {},
          onAction: (action, profile) => actions.add((action, profile)),
          onModifiersChanged: modifiers.add,
        ),
      ),
    ));
    await tester.tap(find.text('Ctrl'));
    expect(modifiers.last, {DuoDeskModifier.control});
    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('duodesk-trackpad'))));
    await tester.pump(const Duration(milliseconds: 600));
    expect(drag.last, isTrue);
    await gesture.cancel();
    expect(drag.last, isFalse);
    await tester.tap(find.text('Ctrl'));
    await tester.tap(find.byTooltip('ドラッグロック'));
    expect(drag.last, isTrue);
    await tester.tap(find.text('Terminal'));
    await tester.pump();
    expect(resets, greaterThan(0));
    expect(drag.last, isFalse);
    expect(modifiers.last, isEmpty);
    await tester.tap(find.text('Ctrl+C'));
    expect(actions.last, (DuoDeskAction.interrupt, DuoDeskProfile.terminal));
  });

  testWidgets('clicks release drag lock before sending another mouse press',
      (tester) async {
    final events = <String>[];
    await tester.binding.setSurfaceSize(const Size(760, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DuoDeskWorkspace(
          viewport: const SizedBox(),
          onViewportChanged: (_) {},
          onMove: (_) {},
          onScroll: (_) {},
          onLeftClick: () => events.add('left'),
          onRightClick: () => events.add('right'),
          onKeyboard: () {},
          onResetInput: () {},
          onDrag: (down) => events.add(down ? 'down' : 'up'),
          onKey: (_) {},
          onAction: (_, __) {},
          onModifiersChanged: (_) {},
        ),
      ),
    ));
    for (final (target, right) in [
      (find.byKey(const ValueKey('duodesk-trackpad')), false),
      (find.text('左クリック'), false),
      (find.byKey(const ValueKey('duodesk-right-click')), true),
    ]) {
      events.clear();
      await tester.tap(find.byTooltip('ドラッグロック'));
      await tester.pump();
      await tester.tap(target);
      await tester.pump();
      expect(events, right ? ['down', 'up', 'right'] : ['down', 'up']);
      expect(find.text('ドラッグ中'), findsNothing);
    }
  });
}
