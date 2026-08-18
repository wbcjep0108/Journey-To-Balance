import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_currency.dart';
import '../../providers/currency_provider.dart';

class CurrencySettingsPage extends StatefulWidget {
  const CurrencySettingsPage({super.key});

  @override
  State<CurrencySettingsPage> createState() => _CurrencySettingsPageState();
}

class _CurrencySettingsPageState extends State<CurrencySettingsPage> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AppCurrency> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return AppCurrency.all;
    return AppCurrency.all
        .where((currency) => currency.searchText.contains(q))
        .toList();
  }

  Future<void> _select(AppCurrency currency) async {
    await context.read<CurrencyProvider>().setCurrency(currency);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Currency set to ${currency.name} (${currency.code}).'),
        ),
      );
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final selected = context.watch<CurrencyProvider>().currency;
    final currencies = _filtered;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F2F4),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF1F2F4),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
        title: const Text(
          'Currency',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search currency',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: currencies.isEmpty
                ? const Center(
                    child: Text(
                      'No currencies found.',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    itemCount: currencies.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final currency = currencies[index];
                      final isSelected = currency.code == selected.code;
                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          onTap: () => _select(currency),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F2F4),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(
                                    currency.symbol.trim(),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF121212),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        currency.name,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF121212),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        currency.code,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF6B7280),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: Color(0xFF121212),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
