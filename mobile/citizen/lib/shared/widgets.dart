import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:jardem_core/jardem_core.dart';

/// Back chevron + centred title, as on the inner screens of the mock-up.
///
/// When the screen was opened directly (deep link, or after `go`), the chevron
/// leads to [fallbackLocation] instead of popping.
class JardemAppBar extends StatelessWidget implements PreferredSizeWidget {
  const JardemAppBar({super.key, required this.title, this.actions, this.fallbackLocation});

  final String title;
  final List<Widget>? actions;
  final String? fallbackLocation;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final fallback = fallbackLocation;
    return AppBar(
      toolbarHeight: 52,
      automaticallyImplyLeading: false,
      leading: canPop || fallback != null
          ? IconButton(
              tooltip: 'Назад',
              icon: const Icon(Icons.chevron_left_rounded, size: 30),
              onPressed: () => canPop ? Navigator.of(context).maybePop() : GoRouter.of(context).go(fallback!),
            )
          : null,
      title: Text(title),
      actions: actions,
    );
  }
}

/// Horizontally scrolling pill chips (categories).
class PillChips<T> extends StatelessWidget {
  const PillChips({
    super.key,
    required this.items,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.color = JardemColors.primary,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.outlined = false,
  });

  final List<T> items;
  final T? selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;
  final Color color;
  final EdgeInsets padding;

  /// Segmented-control look of the call form (outline instead of fill).
  final bool outlined;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: outlined ? 40 : 36,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: padding,
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, i) {
        final item = items[i];
        final on = item == selected;
        final Color bg, fg, border;
        if (outlined) {
          bg = on ? Color.lerp(color, Colors.white, 0.92)! : Colors.white;
          fg = on ? color : JardemColors.muted;
          border = on ? color : JardemColors.border;
        } else {
          bg = on ? color : Colors.white;
          fg = on ? Colors.white : JardemColors.navy;
          border = on ? color : Colors.transparent;
        }
        return Material(
          color: bg,
          elevation: outlined || on ? 0 : 1.5,
          shadowColor: const Color(0x331A4B8C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(outlined ? 12 : 999),
            side: BorderSide(color: border, width: outlined ? 1.5 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onSelected(item),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: outlined ? 18 : 14),
              child: Center(
                child: Text(
                  labelOf(item),
                  style: JardemTheme.text(13, on ? FontWeight.w700 : FontWeight.w600, color: fg),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Form field label such as «Что произошло?».
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6, top: 14),
    child: Text(text, style: JardemTheme.text(13, FontWeight.w700)),
  );
}
