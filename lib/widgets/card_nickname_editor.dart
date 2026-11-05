import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../providers/wallet_cards_provider.dart';
import 'barrier_blur.dart';

/// Result of the nickname editor. [value] is the normalized nickname, or null
/// when the user cleared it (so the card falls back to its bank name).
class CardNicknameResult {
  const CardNicknameResult(this.value);
  final String? value;
}

/// Shows a small single-field dialog to edit a card nickname. Returns null when
/// the user cancels, or a [CardNicknameResult] when they save.
Future<CardNicknameResult?> showCardNicknameEditor({
  required BuildContext context,
  required String? currentNickname,
  required String bankLabel,
}) {
  return showDialog<CardNicknameResult>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => withBarrierBlur(
      _CardNicknameDialog(
        currentNickname: currentNickname,
        bankLabel: bankLabel,
      ),
    ),
  );
}

class _CardNicknameDialog extends StatefulWidget {
  const _CardNicknameDialog({
    required this.currentNickname,
    required this.bankLabel,
  });

  final String? currentNickname;
  final String bankLabel;

  @override
  State<_CardNicknameDialog> createState() => _CardNicknameDialogState();
}

class _CardNicknameDialogState extends State<_CardNicknameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentNickname ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.pop(
      context,
      CardNicknameResult(normalizeCardNickname(_controller.text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Card nickname',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: Color(0xFF121212),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: kWalletCardNicknameMaxLength,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              inputFormatters: [
                LengthLimitingTextInputFormatter(
                  kWalletCardNicknameMaxLength,
                ),
              ],
              decoration: InputDecoration(
                hintText: widget.bankLabel,
                filled: true,
                fillColor: const Color(0xFFF3F4F6),
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Leave blank to use "${widget.bankLabel}".',
              style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF121212),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: const Text(
                      'Save',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
