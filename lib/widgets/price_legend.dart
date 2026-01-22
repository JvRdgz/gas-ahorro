import 'package:flutter/material.dart';

import '../utils/price_color.dart';

class PriceLegend extends StatelessWidget {
  const PriceLegend({
    super.key,
    required this.minPrice,
    required this.maxPrice,
  });

  final double minPrice;
  final double maxPrice;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendDot(color: PriceColor.colorFor(minPrice, minPrice, maxPrice)),
          const SizedBox(width: 6),
          Text('Mas barata'),
          const SizedBox(width: 12),
          _LegendDot(color: PriceColor.colorFor(maxPrice, minPrice, maxPrice)),
          const SizedBox(width: 6),
          Text('Mas cara'),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
