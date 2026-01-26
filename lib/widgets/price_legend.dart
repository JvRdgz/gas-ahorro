import 'package:flutter/material.dart';

import '../utils/price_color.dart';

class PriceLegend extends StatelessWidget {
  const PriceLegend({
    super.key,
    required this.minPrice,
    required this.maxPrice,
    this.label,
    this.backgroundColor,
    this.textColor,
    this.secondaryTextColor,
    this.shadowColor,
    this.borderColor,
  });

  final double minPrice;
  final double maxPrice;
  final String? label;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? secondaryTextColor;
  final Color? shadowColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        border: borderColor == null ? null : Border.all(color: borderColor!),
        boxShadow: [
          BoxShadow(
            color: (shadowColor ?? Colors.black26).withOpacity(0.6),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null && label!.isNotEmpty) ...[
            Text(
              label!,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: textColor,
                  ),
            ),
            const SizedBox(height: 6),
          ],
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LegendDot(
                color: PriceColor.colorFor(minPrice, minPrice, maxPrice),
              ),
              const SizedBox(width: 6),
              Text(
                'Mas barata',
                style: TextStyle(color: secondaryTextColor ?? textColor),
              ),
              const SizedBox(width: 12),
              _LegendDot(
                color: PriceColor.colorFor(maxPrice, minPrice, maxPrice),
              ),
              const SizedBox(width: 6),
              Text(
                'Mas cara',
                style: TextStyle(color: secondaryTextColor ?? textColor),
              ),
            ],
          ),
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
