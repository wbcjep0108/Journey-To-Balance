import 'package:flutter/material.dart';

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
          _CircleIcon(assetPath: iconAsset!, size: iconSize),
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

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.assetPath, required this.size});

  final String assetPath;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: Padding(
        padding: EdgeInsets.all(size * 0.16),
        child: Image.asset(
          assetPath,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Icon(
            Icons.category_outlined,
            size: size * 0.45,
            color: const Color(0xFF737983),
          ),
        ),
      ),
    );
  }
}
