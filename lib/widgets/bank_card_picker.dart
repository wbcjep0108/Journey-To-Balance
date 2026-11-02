import 'package:flutter/material.dart';

const bankCardIconAssets = <String>[
  'assets/images/bank/landbank.png',
  'assets/images/bank/bdo.png',
  'assets/images/bank/metrobank.png',
  'assets/images/bank/bpi.png',
  'assets/images/bank/unionbank.png',
  'assets/images/bank/gcash.png',
  'assets/images/bank/gotyme.png',
  'assets/images/bank/maya.png',
  'assets/images/bank/maribank.png',
  'assets/images/bank/pnb.png',
];

class BankCardPickerTile extends StatelessWidget {
  const BankCardPickerTile({
    super.key,
    required this.iconAsset,
    required this.selected,
    required this.onTap,
    this.alreadyAdded = false,
  });

  final String iconAsset;
  final bool selected;
  final bool alreadyAdded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: iconAsset.split('/').last.replaceAll('.png', ''),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? const Color(0xFF111827) : Colors.transparent,
              width: 2,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  iconAsset,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: Color(0xFFE5E7EB),
                    child: Icon(Icons.account_balance_outlined),
                  ),
                ),
              ),
              if (alreadyAdded)
                const Positioned(
                  right: 8,
                  top: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xFF111827),
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
