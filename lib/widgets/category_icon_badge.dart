import 'package:flutter/material.dart';

import '../models/spend_category_option.dart';

/// Renders a category icon from a PNG asset or a material sentinel path.
class CategoryIconBadge extends StatelessWidget {
  const CategoryIconBadge({
    super.key,
    required this.iconAsset,
    this.size = 34,
    this.iconColor = const Color(0xFF25282D),
    this.backgroundColor = Colors.white,
    this.showBorder = true,
  });

  final String iconAsset;
  final double size;
  final Color iconColor;
  final Color backgroundColor;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final isMaterial = SpendCategoryOption.isMaterialAsset(iconAsset);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: showBorder ? Border.all(color: const Color(0xFFE5E7EB)) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: isMaterial
          ? Icon(
              SpendCategoryOption.materialIconForAsset(iconAsset),
              size: size * 0.5,
              color: iconColor,
            )
          : Padding(
              padding: EdgeInsets.all(size * 0.16),
              child: Image.asset(
                iconAsset,
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
