import 'package:flutter/material.dart';

import '../models/station.dart';

class StationSheet extends StatelessWidget {
  const StationSheet({
    super.key,
    required this.station,
    required this.markerColor,
    required this.onNavigate,
  });

  final Station station;
  final Color markerColor;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          8 + MediaQuery.of(context).viewPadding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: markerColor,
                  child: const Icon(
                    Icons.local_gas_station,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    station.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              station.address,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (station.isRestricted)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3CD),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFE8A1)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFF8A6D3B),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Venta restringida: solo flotas o clientes autorizados.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF8A6D3B),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            if (station.isRestricted) const SizedBox(height: 12),
            if (station.prices.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: station.prices.entries.map((entry) {
                  return Chip(
                    label: Text(
                      '${entry.key}: ${entry.value.toStringAsFixed(3)}',
                    ),
                  );
                }).toList(),
              )
            else
              Text(
                'Sin precios disponibles.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            const SizedBox(height: 12),
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
