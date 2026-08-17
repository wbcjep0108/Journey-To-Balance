import 'package:flutter/material.dart';

import 'category_icon_badge.dart';

/// Circular category icon + title, matching the dark transaction list style.
class EntryTitleWithIcon extends StatelessWidget {
  const EntryTitleWithIcon({
    super.key,
    required this.title,
    this.iconAsset,
    this.titleStyle,
    this.iconSize = 34,
    this.spacing = 12,
  });

  final String title;
  final String? iconAsset;
  final TextStyle? titleStyle;
  final double iconSize;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final style =
        titleStyle ??
        const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        );

    return Row(
      children: [
        if (iconAsset != null && iconAsset!.isNotEmpty) ...[
          CategoryIconBadge(
            iconAsset: iconAsset!,
            size: iconSize,
            showBorder: false,
          ),
          SizedBox(width: spacing),
        ],
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}
