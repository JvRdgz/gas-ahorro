import 'package:flutter/material.dart';

import '../models/place_prediction.dart';
/// Autocomplete suggestion list.
class PredictionsList extends StatelessWidget {
  const PredictionsList({
    super.key,
    required this.isLoading,
    required this.predictions,
    required this.onSelected,
    required this.maxHeight,
  });

  final bool isLoading;
  final List<PlacePrediction> predictions;
  final ValueChanged<PlacePrediction> onSelected;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: isLoading
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          : ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: predictions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final prediction = predictions[index];
                return ListTile(
                  leading: Icon(Icons.place, color: colorScheme.onSurfaceVariant),
                  title: Text(
                    prediction.primaryText,
                    style: TextStyle(color: colorScheme.onSurface),
                  ),
                  subtitle: prediction.secondaryText.isEmpty
                      ? null
                      : Text(
                          prediction.secondaryText,
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                  onTap: () => onSelected(prediction),
                );
              },
            ),
    );
  }
}
