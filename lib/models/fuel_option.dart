import 'package:flutter/material.dart';

/// Fuel types shown in filters and used for price lookup.
enum FuelOptionId {
  gasolina95,
  gasolina98,
  gasoleoA,
  gasoleoPremium,
  glp,
  gnc,
}

/// UI model for each fuel option chip.
class FuelOption {
  const FuelOption({
    required this.id,
    required this.label,
    required this.color,
  });

  final FuelOptionId id;
  final String label;
  final Color color;
}
