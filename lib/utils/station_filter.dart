/// Filters entries for the "cheapest" option and returns indices + min/max.
Map<String, dynamic> filterStationsForSelection(
  Map<String, dynamic> input,
) {
  final entries = (input['entries'] as List)
      .cast<Map>()
      .map((entry) => (
            index: entry['index'] as int,
            price: (entry['price'] as num).toDouble(),
          ))
      .toList();
  if (entries.isEmpty) {
    return {
      'indices': <int>[],
      'minPrice': 0.0,
      'maxPrice': 0.0,
    };
  }

  var filtered = entries;
  final filterCheapestOnly = input['filterCheapestOnly'] as bool? ?? false;
  if (filterCheapestOnly) {
    final prices = entries.map((entry) => entry.price).toList()..sort();
    final cutoffIndex = ((prices.length - 1) * 0.25).round();
    final cutoff = prices[cutoffIndex];
    filtered = entries.where((entry) => entry.price <= cutoff).toList();
  }

  if (filtered.isEmpty) {
    return {
      'indices': <int>[],
      'minPrice': 0.0,
      'maxPrice': 0.0,
    };
  }

  var minPrice = filtered.first.price;
  var maxPrice = filtered.first.price;
  for (final entry in filtered.skip(1)) {
    if (entry.price < minPrice) minPrice = entry.price;
    if (entry.price > maxPrice) maxPrice = entry.price;
  }

  return {
    'indices': filtered.map((entry) => entry.index).toList(),
    'minPrice': minPrice,
    'maxPrice': maxPrice,
  };
}
