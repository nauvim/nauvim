import 'package:material_ui/material_ui.dart';

import '../../nauvim.dart';
import 'theme.dart';

/// Builds a completion row's content from unmodified host fields.
typedef NauvimCompletionItemBuilder = Widget Function(
  BuildContext context,
  DisplayCompletion item,
  bool selected,
);

class NauvimCompletionMenu extends StatelessWidget {
  const NauvimCompletionMenu({
    super.key,
    required this.popup,
    required this.style,
    required this.onSelected,
    this.itemBuilder,
  });

  final DisplayWidget popup;
  final TextStyle style;
  final ValueChanged<int> onSelected;
  final NauvimCompletionItemBuilder? itemBuilder;

  @override
  Widget build(BuildContext context) {
    final appearance = NauvimTheme.of(context);
    final completions = popup.completions;
    return Material(
      elevation: appearance.popupElevation,
      color: appearance.popupColor,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: appearance.popupMaxHeight,
          maxWidth: appearance.popupMaxWidth,
        ),
        child: ListView.builder(
          primary: false,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: completions?.length ?? popup.items.length,
          itemBuilder: (context, index) {
            final item =
                completions?[index] ??
                DisplayCompletion(
                  word: popup.items[index],
                  kind: '',
                  menu: '',
                  info: index < popup.chunks.length
                      ? popup.chunks[index].text
                      : '',
                );
            final selected = index == popup.selected;
            final content =
                itemBuilder?.call(context, item, selected) ??
                Text(
                  completions == null
                      ? item.word
                      : '${item.word} ${item.kind} ${item.menu}',
                  style: style,
                );
            return Tooltip(
              message: item.info,
              child: InkWell(
                onTap: () => onSelected(index),
                child: Container(
                  color: selected ? appearance.selectedCompletionColor : null,
                  padding: appearance.completionPadding,
                  child: DefaultTextStyle.merge(style: style, child: content),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
