import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/budget_provider.dart';
import '../../providers/currency_provider.dart';
import '../../providers/wallet_cards_provider.dart';
import '../../providers/wallet_cash_provider.dart';
import '../../widgets/allocation_confirm_dialog.dart';
import '../../widgets/barrier_blur.dart';
import '../../widgets/sensitive_action_auth.dart';

Future<bool> _confirmWalletFunding({
  required BuildContext context,
  required double walletCash,
  required List<WalletCardModel> cards,
  required String authTitle,
  required String authDescription,
}) async {
  final budget = context.read<BudgetProvider>();
  final confirmed = await AllocationConfirmDialog.showWalletSourcesConfirm(
    context: context,
    walletCash: walletCash,
    cards: [
      for (final card in cards) (card.bankLabel, card.amount),
    ],
    billsPercentage: budget.billsPercentage,
    savingsPercentage: budget.savingsPercentage,
    personalPercentage: budget.personalPercentage,
  );
  if (confirmed != true) return false;
  if (!context.mounted) return false;

  await Future<void>.delayed(Duration.zero);
  if (!context.mounted) return false;

  final authorized = await showSensitiveActionAuth(
    context: context,
    title: authTitle,
    description: authDescription,
  );
  return authorized == true;
}

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  static const closeAsset = 'assets/images/wallet/wallet_close.png';
  static const openAsset = 'assets/images/wallet/wallet_open.png';
  static const cashAsset = 'assets/images/wallet/cash.png';

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  static const _gradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF3A3A3A), Color(0xFF0A0A0A)],
  );

  int _selectedIndex = 0;

  void _cycleCard(int delta, int cardCount) {
    if (cardCount <= 1) return;
    setState(() {
      _selectedIndex =
          (_selectedIndex + delta + cardCount * 8) % cardCount;
    });
  }

  Future<void> _openCardPopup() async {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final cards = context.read<WalletCardsProvider>().cards;
    if (cards.isEmpty) return;
    final card = cards[_selectedIndex.clamp(0, cards.length - 1)];

    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close card',
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, _, _) => withBarrierBlur(
        SafeArea(
          child: _BankCardPopup(
            cardId: card.id,
            iconAsset: card.iconAsset,
            onDismiss: () => Navigator.pop(dialogContext),
          ),
        ),
      ),
      transitionBuilder: (_, animation, _, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curve),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _openWalletPopup() async {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close wallet',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, _, _) => withBarrierBlur(
        SafeArea(
          child: _WalletOpenPopup(
            reduceMotion: reduceMotion,
            onDismiss: () => Navigator.pop(dialogContext),
          ),
        ),
      ),
      transitionBuilder: (_, animation, _, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curve),
            child: child,
          ),
        );
      },
    );
  }

  void _clampSelectedIndex(int cardCount) {
    if (cardCount <= 0) {
      _selectedIndex = 0;
      return;
    }
    _selectedIndex = _selectedIndex.clamp(0, cardCount - 1);
  }

  Future<void> _applyCardSheetChanges({
    required Set<String> toRemove,
    required String? toAdd,
  }) async {
    final provider = context.read<WalletCardsProvider>();
    final cash = context.read<WalletCashProvider>().amount;
    var removedAmount = 0.0;
    for (final iconAsset in toRemove) {
      removedAmount += provider.cards
          .where((c) => c.iconAsset == iconAsset)
          .fold<double>(0, (sum, c) => sum + c.amount);
      await provider.removeByIconAsset(iconAsset);
    }

    if (toAdd != null && !provider.hasIcon(toAdd)) {
      await provider.addCard(iconAsset: toAdd);
    }

    if (!mounted) return;
    setState(() {
      if (toAdd != null && provider.cards.isNotEmpty) {
        _selectedIndex = provider.cards.length - 1;
      } else {
        _clampSelectedIndex(provider.cards.length);
      }
    });

    final nextTotal = provider.combinedTotal(cash);
    if (removedAmount > 0.001 ||
        (context.read<BudgetProvider>().availableBalance - nextTotal).abs() >
            0.001) {
      try {
        await context.read<BudgetProvider>().updateAvailableBalance(nextTotal);
      } catch (_) {}
    }
  }

  Future<void> _showAddCardSheet() async {
    const banks = <String>[
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

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        String? pendingAdd;
        final pendingRemove = <String>{};
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final wallet = context.watch<WalletCardsProvider>();
            final addedIcons = wallet.cards.map((c) => c.iconAsset).toSet();
            final canDone =
                pendingAdd != null || pendingRemove.isNotEmpty;
            return withBarrierBlur(
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                  child: Container(
                    height: MediaQuery.sizeOf(context).height * 0.52,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF1F2F4),
                      borderRadius: BorderRadius.all(Radius.circular(26)),
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        Center(
                          child: Container(
                            width: 46,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius:
                                  BorderRadius.circular(999),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Add Card',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: GridView.count(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: _BankCardArt.aspectRatio,
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                            children: [
                              for (final iconAsset in banks)
                                _BankPickTile(
                                  iconAsset: iconAsset,
                                  selected: pendingAdd == iconAsset ||
                                      (addedIcons.contains(iconAsset) &&
                                          !pendingRemove.contains(iconAsset)),
                                  alreadyAdded:
                                      addedIcons.contains(iconAsset) &&
                                      !pendingRemove.contains(iconAsset),
                                  onTap: () {
                                    if (addedIcons.contains(iconAsset)) {
                                      setSheetState(() {
                                        if (pendingRemove.contains(iconAsset)) {
                                          pendingRemove.remove(iconAsset);
                                        } else {
                                          pendingRemove.add(iconAsset);
                                        }
                                        if (pendingAdd == iconAsset) {
                                          pendingAdd = null;
                                        }
                                      });
                                      return;
                                    }
                                    setSheetState(() {
                                      pendingAdd = pendingAdd == iconAsset
                                          ? null
                                          : iconAsset;
                                    });
                                  },
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: () =>
                                      Navigator.pop(sheetContext),
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF6B7280),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: !canDone
                                      ? null
                                      : () async {
                                          final pageContext = this.context;
                                          final nav =
                                              Navigator.of(sheetContext);
                                          if (pendingRemove.isNotEmpty) {
                                            final cardsProvider = pageContext
                                                .read<WalletCardsProvider>();
                                            final cash = pageContext
                                                .read<WalletCashProvider>()
                                                .amount;
                                            final budget = pageContext
                                                .read<BudgetProvider>();
                                            final removing = cardsProvider
                                                .cards
                                                .where(
                                                  (card) => pendingRemove
                                                      .contains(card.iconAsset),
                                                )
                                                .toList();
                                            final nextTotal = cash +
                                                cardsProvider.cards
                                                    .where(
                                                      (card) => !pendingRemove
                                                          .contains(
                                                        card.iconAsset,
                                                      ),
                                                    )
                                                    .fold<double>(
                                                      0,
                                                      (sum, card) =>
                                                          sum + card.amount,
                                                    );

                                            final warned =
                                                await AllocationConfirmDialog
                                                    .showDeleteCardsWarning(
                                              context: pageContext,
                                              cardsToRemove: [
                                                for (final card in removing)
                                                  (
                                                    card.bankLabel,
                                                    card.amount,
                                                  ),
                                              ],
                                              currentAvailable:
                                                  budget.availableBalance,
                                              nextAvailable: nextTotal,
                                            );
                                            if (warned != true) return;
                                            if (!mounted) return;

                                            final authorized =
                                                await showSensitiveActionAuth(
                                              context: pageContext,
                                              title: 'Confirm delete card',
                                              description:
                                                  'Enter your PIN or use fingerprint to delete the card, remove its amount, and update your available balance.',
                                            );
                                            if (authorized != true) return;
                                          }

                                          if (!mounted) return;
                                          await _applyCardSheetChanges(
                                            toRemove: Set<String>.from(
                                              pendingRemove,
                                            ),
                                            toAdd: pendingAdd,
                                          );
                                          if (!mounted) return;
                                          nav.pop();
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF121212),
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor:
                                        const Color(0xFFD1D5DB),
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                  child: const Text(
                                    'Done',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final budget = context.watch<BudgetProvider>();
    final currency = context.watch<CurrencyProvider>();
    final walletCards = context.watch<WalletCardsProvider>();
    final walletCash = context.watch<WalletCashProvider>();

    final cards = walletCards.cards;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F3),
      body: Padding(
        padding: EdgeInsets.fromLTRB(10, topInset + 8, 10, bottomInset + 10),
        child: Column(
          children: [
            Expanded(
              flex: 10,
              child: _DarkCard(
                gradient: _gradient,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: GestureDetector(
                          onTap: _openWalletPopup,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                WalletPage.closeAsset,
                                width: 168,
                                height: 168,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                'Your wallet',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Center(child: _Pill()),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            Expanded(
              flex: 10,
              child: _DarkCard(
                gradient: _gradient,
                child: Column(
                  children: [
                    const SizedBox(height: 6),
                    Center(
                      child: ElevatedButton.icon(
                        onPressed: _showAddCardSheet,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text(
                          'Add Card',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF111827),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 12,
                          ),
                          shape: const StadiumBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: cards.isEmpty
                          ? const Center(
                              child: Text(
                                'Add a card to get started',
                                style: TextStyle(
                                  color: Color(0xFFB5B5B5),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          : _StackedCardDeck(
                              cards: cards,
                              selectedIndex: _selectedIndex.clamp(
                                0,
                                cards.length - 1,
                              ),
                              currencySymbol: currency.symbol,
                              onSelect: (index) {
                                setState(() => _selectedIndex = index);
                              },
                              onFrontTap: _openCardPopup,
                              onSwipe: (delta) =>
                                  _cycleCard(delta, cards.length),
                            ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Wallet: ${currency.formatAmount(walletCash.amount)}',
                      style: const TextStyle(
                        color: Color(0xFFB5B5B5),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      'Cards: ${currency.formatAmount(walletCards.totalAmount)}',
                      style: const TextStyle(
                        color: Color(0xFFB5B5B5),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      'Available balance: ${currency.formatAmount(budget.availableBalance)}',
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

class _StackedCardDeck extends StatelessWidget {
  const _StackedCardDeck({
    required this.cards,
    required this.selectedIndex,
    required this.currencySymbol,
    required this.onSelect,
    required this.onFrontTap,
    required this.onSwipe,
  });

  final List<WalletCardModel> cards;
  final int selectedIndex;
  final String currencySymbol;
  final ValueChanged<int> onSelect;
  final VoidCallback onFrontTap;
  final ValueChanged<int> onSwipe;

  static const _stepX = 16.0;
  static const _stepY = 14.0;
  static const _maxVisible = 7;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final visible = math.min(_maxVisible, cards.length);
        final extraW = (visible - 1) * _stepX;
        final extraH = (visible - 1) * _stepY;
        final maxCardW = math.max(0.0, constraints.maxWidth - extraW);
        final maxCardH = math.max(0.0, constraints.maxHeight - extraH);

        var cardW = maxCardW;
        var cardH = cardW / _BankCardArt.aspectRatio;
        if (cardH > maxCardH) {
          cardH = maxCardH;
          cardW = cardH * _BankCardArt.aspectRatio;
        }

        final stackW = cardW + extraW;
        final stackH = cardH + extraH;
        final originX = (constraints.maxWidth - stackW) / 2;
        final originY = (constraints.maxHeight - stackH) / 2;

        return GestureDetector(
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity < -180) {
              onSwipe(1);
            } else if (velocity > 180) {
              onSwipe(-1);
            }
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var depthFromFront = visible - 1;
                  depthFromFront >= 0;
                  depthFromFront--)
                () {
                  final index =
                      (selectedIndex - depthFromFront + cards.length) %
                      cards.length;
                  final card = cards[index];
                  final layer = visible - 1 - depthFromFront;
                  final isFront = depthFromFront == 0;

                  return AnimatedPositioned(
                    key: ValueKey(card.id),
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    left: originX + layer * _stepX,
                    top: originY + layer * _stepY,
                    width: cardW,
                    height: cardH,
                    child: _WalletCardPreview(
                      iconAsset: card.iconAsset,
                      currencySymbol: currencySymbol,
                      amount: card.amount,
                      isFront: isFront,
                      onTap: () {
                        if (isFront) {
                          onFrontTap();
                        } else {
                          onSelect(index);
                        }
                      },
                    ),
                  );
                }(),
            ],
          ),
        );
      },
    );
  }
}

class _WalletCardPreview extends StatelessWidget {
  const _WalletCardPreview({
    required this.iconAsset,
    required this.currencySymbol,
    required this.amount,
    required this.isFront,
    required this.onTap,
  });

  final String iconAsset;
  final String currencySymbol;
  final double amount;
  final bool isFront;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: _BankCardArt.aspectRatio,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isFront ? 0.18 : 0.08),
                blurRadius: isFront ? 10 : 6,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _BankCardArt(assetPath: iconAsset),
              if (isFront)
                Positioned(
                  left: 16,
                  bottom: 14,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF111827).withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Text(
                        '$currencySymbol${NumberFormat('#,##0').format(amount)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
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

/// Bank PNGs are already card-sized (~3:2). Cover the frame so no letterbox gaps.
class _BankCardArt extends StatelessWidget {
  const _BankCardArt({
    required this.assetPath,
    this.borderRadius = 18,
  });

  final String assetPath;
  final double borderRadius;

  static const aspectRatio = 3 / 2;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox.expand(
        child: Image.asset(
          assetPath,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

class _BankCardPopup extends StatefulWidget {
  const _BankCardPopup({
    required this.cardId,
    required this.iconAsset,
    required this.onDismiss,
  });

  final String cardId;
  final String iconAsset;
  final VoidCallback onDismiss;

  @override
  State<_BankCardPopup> createState() => _BankCardPopupState();
}

class _BankCardPopupState extends State<_BankCardPopup> {
  late final TextEditingController _amountController;
  late final FocusNode _amountFocus;

  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final cash =
        context.read<WalletCardsProvider>().cardById(widget.cardId)?.amount ??
        0;
    _amountController = TextEditingController(
      text: cash == 0 ? '' : NumberFormat('#,##0.##').format(cash),
    );
    _amountFocus = FocusNode();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  Future<void> _startEditing() async {
    if (_saving) return;
    final cash =
        context.read<WalletCardsProvider>().cardById(widget.cardId)?.amount ??
        0;
    _amountController.text =
        cash == 0 ? '' : NumberFormat('#,##0.##').format(cash);
    setState(() => _editing = true);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (mounted) _amountFocus.requestFocus();
  }

  Future<void> _saveAmount() async {
    if (_saving) return;
    setState(() => _saving = true);

    final raw = _amountController.text.replaceAll(',', '').trim();
    final parsed = double.tryParse(raw) ?? 0;

    final cards = context.read<WalletCardsProvider>();
    final cash = context.read<WalletCashProvider>().amount;
    final previewCards = [
      for (final card in cards.cards)
        card.id == widget.cardId ? card.copyWith(amount: parsed) : card,
    ];

    final confirmed = await _confirmWalletFunding(
      context: context,
      walletCash: cash,
      cards: previewCards,
      authTitle: 'Confirm card update',
      authDescription:
          'Enter your PIN or use fingerprint to update this card and reallocate your budget.',
    );

    if (!mounted) return;
    if (!confirmed) {
      setState(() => _saving = false);
      return;
    }

    try {
      await cards.setCardAmount(cardId: widget.cardId, amount: parsed);
      await context.read<BudgetProvider>().updateAvailableBalance(
        cards.combinedTotal(cash),
      );

      if (!mounted) return;
      setState(() => _editing = false);
      widget.onDismiss();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save wallet update: $e')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = context.watch<CurrencyProvider>();
    final cardAmount =
        context.watch<WalletCardsProvider>().cardById(widget.cardId)?.amount ??
        0;
    final amountLabel = NumberFormat('#,##0').format(cardAmount);

    return GestureDetector(
      onTap: () {
        if (_editing) {
          _saveAmount();
          return;
        }
        widget.onDismiss();
      },
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: GestureDetector(
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Material(
              color: Colors.transparent,
              child: AspectRatio(
                aspectRatio: _BankCardArt.aspectRatio,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFF4B5563),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(17),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _BankCardArt(assetPath: widget.iconAsset),
                        Positioned(
                          left: 20,
                          bottom: 16,
                          right: 88,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Flexible(
                                    child: _editing
                                        ? TextField(
                                            controller: _amountController,
                                            focusNode: _amountFocus,
                                            autofocus: true,
                                            enabled: !_saving,
                                            keyboardType: const TextInputType
                                                .numberWithOptions(
                                              decimal: true,
                                            ),
                                            inputFormatters: [
                                              FilteringTextInputFormatter.allow(
                                                RegExp(r'[0-9.,]'),
                                              ),
                                            ],
                                            style: const TextStyle(
                                              color: Colors.black,
                                              fontSize: 28,
                                              fontWeight: FontWeight.w800,
                                              height: 1,
                                            ),
                                            decoration: InputDecoration(
                                              isDense: true,
                                              border: InputBorder.none,
                                              contentPadding: EdgeInsets.zero,
                                              prefixText: currency.symbol,
                                              prefixStyle: const TextStyle(
                                                color: Colors.black,
                                                fontSize: 28,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            onSubmitted: (_) => _saveAmount(),
                                          )
                                        : Text(
                                            '${currency.symbol}$amountLabel',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.black,
                                              fontSize: 28,
                                              fontWeight: FontWeight.w800,
                                              height: 1,
                                            ),
                                          ),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    onPressed: _saving
                                        ? null
                                        : (_editing
                                            ? _saveAmount
                                            : _startEditing),
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                      minHeight: 28,
                                    ),
                                    icon: Icon(
                                      _editing
                                          ? Icons.check_rounded
                                          : Icons.edit_rounded,
                                      size: 16,
                                      color: Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Remaining money',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WalletOpenPopup extends StatefulWidget {
  const _WalletOpenPopup({
    required this.reduceMotion,
    required this.onDismiss,
  });

  final bool reduceMotion;
  final VoidCallback onDismiss;

  @override
  State<_WalletOpenPopup> createState() => _WalletOpenPopupState();
}

class _WalletOpenPopupState extends State<_WalletOpenPopup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _openProgress;
  late final Animation<double> _billFade;
  late final Animation<double> _walletScale;

  late final TextEditingController _amountController;
  late final FocusNode _amountFocus;

  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final cash = context.read<WalletCashProvider>().amount;
    _amountController = TextEditingController(
      text: cash == 0 ? '' : NumberFormat('#,##0.##').format(cash),
    );
    _amountFocus = FocusNode();

    _controller = AnimationController(
      vsync: this,
      duration: widget.reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 720),
    );
    _openProgress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.55, curve: Curves.easeInOutCubic),
    );
    _billFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.42, 1, curve: Curves.easeOut),
    );
    _walletScale = Tween<double>(begin: 0.88, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.5, curve: Curves.easeOutBack),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _amountController.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  Future<void> _startEditing() async {
    if (_saving) return;
    final cash = context.read<WalletCashProvider>().amount;
    _amountController.text = cash == 0 ? '' : NumberFormat('#,##0.##').format(cash);
    setState(() => _editing = true);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (mounted) _amountFocus.requestFocus();
  }

  Future<void> _saveAmount() async {
    if (_saving) return;
    setState(() => _saving = true);

    final raw = _amountController.text.replaceAll(',', '').trim();
    final parsed = double.tryParse(raw) ?? 0;
    final cards = context.read<WalletCardsProvider>().cards;

    final confirmed = await _confirmWalletFunding(
      context: context,
      walletCash: parsed,
      cards: cards,
      authTitle: 'Confirm wallet update',
      authDescription:
          'Enter your PIN or use fingerprint to update wallet cash and reallocate your budget.',
    );

    if (!mounted) return;
    if (!confirmed) {
      setState(() => _saving = false);
      return;
    }

    try {
      final cashProvider = context.read<WalletCashProvider>();
      await cashProvider.setAmount(parsed);
      await context.read<BudgetProvider>().updateAvailableBalance(
        context.read<WalletCardsProvider>().combinedTotal(cashProvider.amount),
      );

      if (!mounted) return;
      setState(() => _editing = false);
      widget.onDismiss();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save wallet update: $e')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = context.watch<CurrencyProvider>();
    final cashAmount = context.watch<WalletCashProvider>().amount;
    final amountLabel = NumberFormat('#,##0.##').format(cashAmount);

    return GestureDetector(
      onTap: () {
        if (_editing) {
          _saveAmount();
          return;
        }
        widget.onDismiss();
      },
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: GestureDetector(
          onTap: () {},
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: 320,
                  height: 300,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.scale(
                        scale: _walletScale.value,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Opacity(
                              opacity: 1 - _openProgress.value,
                              child: Image.asset(
                                WalletPage.closeAsset,
                                width: 270,
                                fit: BoxFit.contain,
                              ),
                            ),
                            Opacity(
                              opacity: _openProgress.value,
                              child: Image.asset(
                                WalletPage.openAsset,
                                width: 340,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 18,
                        right: 18,
                        top: 108,
                        child: Opacity(
                          opacity: _billFade.value,
                          child: Transform.translate(
                            offset:
                                Offset(0, 16 * (1 - _billFade.value)),
                            child: _CashBill(
                              symbol: currency.symbol,
                              amountLabel: amountLabel,
                              editing: _editing,
                              saving: _saving,
                              controller: _amountController,
                              focusNode: _amountFocus,
                              onEdit: _startEditing,
                              onSubmitted: _saveAmount,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CashBill extends StatelessWidget {
  const _CashBill({
    required this.symbol,
    required this.amountLabel,
    required this.editing,
    required this.saving,
    required this.controller,
    required this.focusNode,
    required this.onEdit,
    required this.onSubmitted,
  });

  final String symbol;
  final String amountLabel;
  final bool editing;
  final bool saving;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onEdit;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.asset(
            WalletPage.cashAsset,
            width: double.infinity,
            height: 92,
            fit: BoxFit.fill,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 18, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  symbol,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: editing
                      ? TextField(
                          controller: controller,
                          focusNode: focusNode,
                          autofocus: true,
                          enabled: !saving,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]'),
                            ),
                          ],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onSubmitted: (_) => onSubmitted(),
                        )
                      : Text(
                          amountLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                ),
                const SizedBox(width: 4),
                Align(
                  alignment: Alignment.topCenter,
                  child: IconButton(
                    onPressed: saving
                        ? null
                        : (editing ? onSubmitted : onEdit),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    icon: Icon(
                      editing ? Icons.check_rounded : Icons.edit_rounded,
                      size: 16,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BankPickTile extends StatelessWidget {
  const _BankPickTile({
    required this.iconAsset,
    required this.selected,
    required this.alreadyAdded,
    required this.onTap,
  });

  final String iconAsset;
  final bool selected;
  final bool alreadyAdded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
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
            _BankCardArt(assetPath: iconAsset, borderRadius: 14),
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
    );
  }
}

class _DarkCard extends StatelessWidget {
  const _DarkCard({required this.gradient, required this.child});

  final Gradient gradient;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(36),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: child,
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

