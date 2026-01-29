class Station {
  Station({
    required this.id,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.prices,
    required this.isRestricted,
  });

  final String id;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final Map<String, double> prices;
  final bool isRestricted;

  double? get bestPrice {
    if (prices.isEmpty) return null;
    return prices.values.reduce((a, b) => a < b ? a : b);
  }

  String? get bestFuelLabel {
    if (prices.isEmpty) return null;
    final best = bestPrice;
    if (best == null) return null;
    return prices.entries
        .firstWhere((entry) => entry.value == best)
        .key;
  }
}
