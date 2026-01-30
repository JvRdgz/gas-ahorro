import 'fuel_option.dart';

/// Result returned by the filter sheet modal.
class FilterResult {
  const FilterResult({
    required this.fuel,
    required this.cheapestOnly,
    required this.includeRestricted,
    required this.showPrices,
    required this.routeRadiusMeters,
  });

  final FuelOptionId? fuel;
  final bool cheapestOnly;
  final bool includeRestricted;
  final bool showPrices;
  final int? routeRadiusMeters;
}
