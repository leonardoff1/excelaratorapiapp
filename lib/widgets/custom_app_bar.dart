// custom_app_bar.dart
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;

  /// When true, renders a transparent, blurred app bar (use with extendBodyBehindAppBar).
  final bool glass;

  const CustomAppBar({
    super.key,
    this.title = 'ExcelaratorAPI',
    this.actions,
    this.glass = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppBar(
      backgroundColor:
          glass ? Colors.transparent : cs.surface.withOpacity(0.95),
      surfaceTintColor: Colors.transparent, // prevent M3 tint shifting
      elevation: 0,
      scrolledUnderElevation: 2,
      centerTitle: false,
      titleSpacing: 0,
      iconTheme: IconThemeData(color: cs.onSurface),
      actionsIconTheme: IconThemeData(color: cs.onSurface),
      systemOverlayStyle:
          isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      flexibleSpace:
          glass
              ? ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(color: cs.surface.withOpacity(0.08)),
                ),
              )
              : null,
      title: Row(
        children: [
          const SizedBox(width: 8),
          SvgPicture.asset(
            'assets/brand/excelarator_mark.svg',
            width: 28,
            height: 28,
            colorFilter: ColorFilter.mode(
              isDark ? Colors.white : cs.primary,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title.isEmpty ? 'ExcelaratorAPI' : title,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
      actions:
          actions
              ?.map(
                (w) =>
                    Padding(padding: const EdgeInsets.only(right: 8), child: w),
              )
              .toList(),
      // subtle bottom divider
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: cs.outline.withOpacity(glass ? 0.18 : 0.24),
        ),
      ),
    );
  }
}
