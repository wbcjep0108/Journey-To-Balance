import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/app_currency.dart';

/// Daily FX rates covering every currency in Account → Currency settings.
class ExchangeRateService {
  ExchangeRateService({http.Client? client}) : _client = client ?? http.Client();

  static const _endpoint = 'https://open.er-api.com/v6/latest/USD';

  static List<AppCurrency> get supportedCurrencies => AppCurrency.all;

  final http.Client _client;
  Map<String, double>? _usdRates;
  DateTime? _fetchedAt;

  Future<Map<String, double>> usdRates({bool force = false}) async {
    final cached = _usdRates;
    final fetchedAt = _fetchedAt;
    if (!force &&
        cached != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < const Duration(hours: 12)) {
      return cached;
    }

    final response = await _client
        .get(Uri.parse(_endpoint))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Could not load exchange rates.');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Could not load exchange rates.');
    }
    final rawRates = decoded['rates'];
    if (rawRates is! Map) {
      throw Exception('Could not load exchange rates.');
    }

    final rates = <String, double>{'USD': 1};
    for (final entry in rawRates.entries) {
      final value = entry.value;
      if (value is num) {
        rates[entry.key.toString()] = value.toDouble();
      }
    }

    _usdRates = rates;
    _fetchedAt = DateTime.now();
    return rates;
  }

  double convert({
    required double amount,
    required String from,
    required String to,
    required Map<String, double> usdRates,
  }) {
    if (from == to) return amount;
    final fromRate = usdRates[from];
    final toRate = usdRates[to];
    if (fromRate == null || toRate == null || fromRate == 0) {
      throw Exception('Missing rate for $from or $to.');
    }
    return amount / fromRate * toRate;
  }
}
