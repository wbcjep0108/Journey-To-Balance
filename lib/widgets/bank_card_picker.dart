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
    this.count = 0,
    this.canRemoveQueued = false,
    this.onRemoveQueued,
  });

  final String iconAsset;
  final bool selected;

  /// Legacy flag (checkmark). Superseded by [count] when it is > 0.
  final bool alreadyAdded;

  /// Total cards of this bank (owned + queued this session). Shows an "xN"
  /// badge when > 0.
  final int count;

  /// Whether a minus affordance should appear (a card is queued this session).
  final bool canRemoveQueued;

  /// Removes the most recently queued card of this bank (session-only).
  final VoidCallback? onRemoveQueued;

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
              if (count > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111827),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'x$count',
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                )
              else if (alreadyAdded)
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
              if (canRemoveQueued)
                Positioned(
                  left: 8,
                  top: 8,
                  child: Semantics(
                    button: true,
                    label: 'Remove queued card',
                    child: GestureDetector(
                      onTap: onRemoveQueued,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.remove_rounded,
                          size: 16,
                          color: Color(0xFF111827),
                        ),
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
