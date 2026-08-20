import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/app_currency.dart';
import '../services/exchange_rate_service.dart';
import 'barrier_blur.dart';

class ForeignExchangeCard extends StatefulWidget {
  const ForeignExchangeCard({super.key});

  @override
  State<ForeignExchangeCard> createState() => _ForeignExchangeCardState();
}

class _ForeignExchangeCardState extends State<ForeignExchangeCard> {
  static final _amountFormat = NumberFormat('#,##0.##');

  final _service = ExchangeRateService();
  final _controllers = List<TextEditingController>.generate(
    3,
    (_) => TextEditingController(),
  );

  late List<AppCurrency> _currencies;
  Map<String, double> _rates = const {};
  int _baseIndex = 0;
  bool _loading = true;
  bool _updating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currencies = [
      AppCurrency.byCode('PHP'),
      AppCurrency.byCode('USD'),
      AppCurrency.byCode('JPY'),
    ];
    _controllers[0].text = '10,000';
    _loadRates();
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadRates() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rates = await _service.usdRates();
      if (!mounted) return;
      setState(() {
        _rates = rates;
        _loading = false;
      });
      _recalculateFrom(_baseIndex);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load exchange rates.';
      });
    }
  }

  double _parseAmount(String raw) {
    return double.tryParse(raw.replaceAll(',', '').trim()) ?? 0;
  }

  void _recalculateFrom(int source) {
    if (_rates.isEmpty) return;
    final amount = _parseAmount(_controllers[source].text);
    _updating = true;
    for (var i = 0; i < _currencies.length; i++) {
      if (i == source) continue;
      try {
        final converted = _service.convert(
          amount: amount,
          from: _currencies[source].code,
          to: _currencies[i].code,
          usdRates: _rates,
        );
        _controllers[i].text = _amountFormat.format(converted);
      } catch (_) {
        _controllers[i].text = '';
      }
    }
    _updating = false;
    _baseIndex = source;
  }

  Future<void> _pickCurrency(int index) async {
    final selected = await showModalBottomSheet<AppCurrency>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final options = AppCurrency.all.where((currency) {
              if (query.trim().isEmpty) return true;
              return currency.searchText.contains(query.trim().toLowerCase());
            }).toList();
            return withBarrierBlur(
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Container(
                height: MediaQuery.sizeOf(sheetContext).height * 0.55,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F8),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1D5DB),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        'Select currency',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(
                        onChanged: (value) =>
                            setSheetState(() => query = value),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search currency',
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: options.isEmpty
                          ? const Center(
                              child: Text(
                                'No currencies found.',
                                style: TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: options.length,
                              itemBuilder: (context, i) {
                                final currency = options[i];
                                final isCurrent =
                                    currency.code == _currencies[index].code;
                                return ListTile(
                                  selected: isCurrent,
                                  selectedColor: const Color(0xFF121212),
                                  selectedTileColor: Colors.transparent,
                                  textColor: const Color(0xFF121212),
                                  iconColor: const Color(0xFF121212),
                                  leading: Text(
                                    currency.symbol.trim(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      color: Color(0xFF121212),
                                    ),
                                  ),
                                  title: Text(
                                    currency.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF121212),
                                    ),
                                  ),
                                  trailing: Text(
                                    currency.code,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF6B7280),
                                    ),
                                  ),
                                  onTap: () =>
                                      Navigator.pop(sheetContext, currency),
                                );
                              },
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
    if (selected == null || !mounted) return;
    setState(() {
      final duplicate = _currencies.indexWhere(
        (currency) => currency.code == selected.code,
      );
      if (duplicate >= 0 && duplicate != index) {
        _currencies[duplicate] = _currencies[index];
      }
      _currencies[index] = selected;
    });
    _recalculateFrom(_baseIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Foreign Exchange',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF121212),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextButton(
                    onPressed: _loadRates,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          else
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _ExchangeRow(
                currency: _currencies[i],
                controller: _controllers[i],
                onPickCurrency: () => _pickCurrency(i),
                onChanged: () {
                  if (_updating) return;
                  _recalculateFrom(i);
                },
              ),
            ],
        ],
      ),
    );
  }
}

class _ExchangeRow extends StatelessWidget {
  const _ExchangeRow({
    required this.currency,
    required this.controller,
    required this.onPickCurrency,
    required this.onChanged,
  });

  final AppCurrency currency;
  final TextEditingController controller;
  final VoidCallback onPickCurrency;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 7,
          child: Container(
            height: 48,
            padding: const EdgeInsets.fromLTRB(14, 0, 4, 0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${currency.name} ${currency.code}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF121212),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onPickCurrency,
                  tooltip: 'Change currency',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  icon: const Icon(
                    Icons.unfold_more,
                    size: 20,
                    color: Color(0xFF111827),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 4,
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF121212),
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.fromLTRB(12, 12, 16, 12),
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
        ),
      ],
    );
  }
}
