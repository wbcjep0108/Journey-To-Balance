class AppCurrency {
  const AppCurrency({
    required this.code,
    required this.name,
    required this.symbol,
    this.locale = 'en_US',
  });

  final String code;
  final String name;
  final String symbol;
  final String locale;

  String get searchText => '$code $name $symbol'.toLowerCase();

  static const php = AppCurrency(
    code: 'PHP',
    name: 'Philippine Peso',
    symbol: '₱',
    locale: 'en_PH',
  );

  static const List<AppCurrency> all = [
    php,
    AppCurrency(code: 'USD', name: 'US Dollar', symbol: '\$', locale: 'en_US'),
    AppCurrency(code: 'EUR', name: 'Euro', symbol: '€', locale: 'en_EU'),
    AppCurrency(code: 'GBP', name: 'British Pound', symbol: '£', locale: 'en_GB'),
    AppCurrency(code: 'JPY', name: 'Japanese Yen', symbol: '¥', locale: 'ja_JP'),
    AppCurrency(code: 'CNY', name: 'Chinese Yuan', symbol: '¥', locale: 'zh_CN'),
    AppCurrency(code: 'KRW', name: 'South Korean Won', symbol: '₩', locale: 'ko_KR'),
    AppCurrency(code: 'AUD', name: 'Australian Dollar', symbol: 'A\$', locale: 'en_AU'),
    AppCurrency(code: 'CAD', name: 'Canadian Dollar', symbol: 'C\$', locale: 'en_CA'),
    AppCurrency(code: 'SGD', name: 'Singapore Dollar', symbol: 'S\$', locale: 'en_SG'),
    AppCurrency(code: 'HKD', name: 'Hong Kong Dollar', symbol: 'HK\$', locale: 'en_HK'),
    AppCurrency(code: 'NZD', name: 'New Zealand Dollar', symbol: 'NZ\$', locale: 'en_NZ'),
    AppCurrency(code: 'CHF', name: 'Swiss Franc', symbol: 'CHF ', locale: 'de_CH'),
    AppCurrency(code: 'INR', name: 'Indian Rupee', symbol: '₹', locale: 'en_IN'),
    AppCurrency(code: 'IDR', name: 'Indonesian Rupiah', symbol: 'Rp', locale: 'id_ID'),
    AppCurrency(code: 'MYR', name: 'Malaysian Ringgit', symbol: 'RM', locale: 'ms_MY'),
    AppCurrency(code: 'THB', name: 'Thai Baht', symbol: '฿', locale: 'th_TH'),
    AppCurrency(code: 'VND', name: 'Vietnamese Dong', symbol: '₫', locale: 'vi_VN'),
    AppCurrency(code: 'AED', name: 'UAE Dirham', symbol: 'AED ', locale: 'ar_AE'),
    AppCurrency(code: 'SAR', name: 'Saudi Riyal', symbol: 'SAR ', locale: 'ar_SA'),
    AppCurrency(code: 'BRL', name: 'Brazilian Real', symbol: 'R\$', locale: 'pt_BR'),
    AppCurrency(code: 'MXN', name: 'Mexican Peso', symbol: 'MX\$', locale: 'es_MX'),
    AppCurrency(code: 'ZAR', name: 'South African Rand', symbol: 'R', locale: 'en_ZA'),
    AppCurrency(code: 'TRY', name: 'Turkish Lira', symbol: '₺', locale: 'tr_TR'),
    AppCurrency(code: 'RUB', name: 'Russian Ruble', symbol: '₽', locale: 'ru_RU'),
    AppCurrency(code: 'PLN', name: 'Polish Zloty', symbol: 'zł', locale: 'pl_PL'),
    AppCurrency(code: 'SEK', name: 'Swedish Krona', symbol: 'kr', locale: 'sv_SE'),
    AppCurrency(code: 'NOK', name: 'Norwegian Krone', symbol: 'kr', locale: 'nb_NO'),
    AppCurrency(code: 'DKK', name: 'Danish Krone', symbol: 'kr', locale: 'da_DK'),
    AppCurrency(code: 'TWD', name: 'New Taiwan Dollar', symbol: 'NT\$', locale: 'zh_TW'),
  ];

  static AppCurrency byCode(String? code) {
    if (code == null || code.isEmpty) return php;
    for (final currency in all) {
      if (currency.code == code) return currency;
    }
    return php;
  }
}
