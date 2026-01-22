import 'package:flutter/material.dart';

import '../models/station.dart';

class StationSheet extends StatelessWidget {
  const StationSheet({
    super.key,
    required this.station,
    required this.onNavigate,
  });

  final Station station;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              station.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              station.address,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (station.prices.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: station.prices.entries.map((entry) {
                  return Chip(
                    label: Text('${entry.key}: ${entry.value.toStringAsFixed(3)}'),
                  );
                }).toList(),
              )
            else
              Text(
                'Sin precios disponibles.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onNavigate,
                icon: const Icon(Icons.navigation),
                label: const Text('Ir'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
