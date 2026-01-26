import 'package:flutter/material.dart';

class PriceColor {
  static double hueFor(double price, double min, double max) {
    if (min == max) return 120;
    final clamped = price.clamp(min, max);
    final t = (clamped - min) / (max - min);
    return 120 - (120 * t);
  }

  static Color colorFor(double price, double min, double max) {
    final hue = hueFor(price, min, max);
    return HSVColor.fromAHSV(1, hue, 0.85, 0.9).toColor();
  }
}
