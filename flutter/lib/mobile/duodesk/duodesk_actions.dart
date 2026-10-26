enum DuoDeskProfile { pointer, terminal }

enum DuoDeskHost { linux, macOS, windows }

enum DuoDeskModifier { control, alt, shift, command }

enum DuoDeskAction {
  copy,
  paste,
  interrupt,
  search,
  lineStart,
  lineEnd,
  tmuxPrefix,
  tmuxNext,
  tmuxPrevious,
}

class DuoDeskStroke {
  final String key;
  final Set<DuoDeskModifier> modifiers;

  const DuoDeskStroke(this.key, [this.modifiers = const {}]);
}

List<DuoDeskStroke> duoDeskShortcut(
    DuoDeskAction action, DuoDeskHost host, DuoDeskProfile profile) {
  const control = {DuoDeskModifier.control};
  final clipboardModifiers = host == DuoDeskHost.macOS
      ? const {DuoDeskModifier.command}
      : host == DuoDeskHost.linux && profile == DuoDeskProfile.terminal
          ? const {DuoDeskModifier.control, DuoDeskModifier.shift}
          : control;
  switch (action) {
    case DuoDeskAction.copy:
      return [DuoDeskStroke('c', clipboardModifiers)];
    case DuoDeskAction.paste:
      return [DuoDeskStroke('v', clipboardModifiers)];
    case DuoDeskAction.interrupt:
      return const [DuoDeskStroke('c', control)];
    case DuoDeskAction.search:
      return const [DuoDeskStroke('r', control)];
    case DuoDeskAction.lineStart:
      return const [DuoDeskStroke('a', control)];
    case DuoDeskAction.lineEnd:
      return const [DuoDeskStroke('e', control)];
    case DuoDeskAction.tmuxPrefix:
      return const [DuoDeskStroke('b', control)];
    case DuoDeskAction.tmuxNext:
      return const [DuoDeskStroke('b', control), DuoDeskStroke('n')];
    case DuoDeskAction.tmuxPrevious:
      return const [DuoDeskStroke('b', control), DuoDeskStroke('p')];
  }
}
