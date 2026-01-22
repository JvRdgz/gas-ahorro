import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'models/station.dart';
import 'services/fuel_api.dart';
import 'services/navigation_launcher.dart';
import 'utils/price_color.dart';
import 'widgets/price_legend.dart';
import 'widgets/station_sheet.dart';

void main() {
  runApp(const GasAhorroApp());
}

class GasAhorroApp extends StatelessWidget {
  const GasAhorroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gas Ahorro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B6E4F)),
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _searchController = TextEditingController();
  final _fuelApi = FuelApi();
  final _launcher = NavigationLauncher();

  Future<List<Station>>? _stationsFuture;
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _stationsFuture = _fuelApi.fetchStations();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<Station>>(
        future: _stationsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(
              message: 'No se pudo cargar la informacion.',
              onRetry: () => setState(() {
                _stationsFuture = _fuelApi.fetchStations();
              }),
            );
          }

          final stations = snapshot.data ?? [];
          if (stations.isEmpty) {
            return _ErrorState(
              message: 'No hay estaciones disponibles.',
              onRetry: () => setState(() {
                _stationsFuture = _fuelApi.fetchStations();
              }),
            );
          }

          final prices = stations
              .map((station) => station.bestPrice)
              .whereType<double>()
              .toList();
          final minPrice = prices.reduce((a, b) => a < b ? a : b);
          final maxPrice = prices.reduce((a, b) => a > b ? a : b);

          return Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(stations.first.lat, stations.first.lng),
                  zoom: 6,
                ),
                onMapCreated: (controller) => _mapController = controller,
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
                markers: stations
                    .where((station) => station.bestPrice != null)
                    .map((station) {
                  final price = station.bestPrice!;
                  final hue = PriceColor.hueFor(price, minPrice, maxPrice);
                  return Marker(
                    markerId: MarkerId(station.id),
                    position: LatLng(station.lat, station.lng),
                    icon: BitmapDescriptor.defaultMarkerWithHue(hue),
                    onTap: () => _showStationSheet(station),
                  );
                }).toSet(),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SearchBar(controller: _searchController),
                      const SizedBox(height: 10),
                      Text(
                        'Escribe tu destino para recomendar gasolineras en ruta',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.black87,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                bottom: 24,
                child: PriceLegend(minPrice: minPrice, maxPrice: maxPrice),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Pendiente de integrar ruta y geocodificacion.'),
            ),
          );
        },
        icon: const Icon(Icons.alt_route),
        label: const Text('Ruta'),
      ),
    );
  }

  void _showStationSheet(Station station) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => StationSheet(
        station: station,
        onNavigate: () => _showNavigationOptions(station),
      ),
    );
  }

  Future<void> _showNavigationOptions(Station station) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.map),
                title: const Text('Google Maps'),
                onTap: () => Navigator.pop(context, 'maps'),
              ),
              ListTile(
                leading: const Icon(Icons.navigation),
                title: const Text('Waze'),
                onTap: () => Navigator.pop(context, 'waze'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || result == null) return;

    final lat = station.lat;
    final lng = station.lng;
    final ok = result == 'waze'
        ? await _launcher.openWaze(lat, lng)
        : await _launcher.openGoogleMaps(lat, lng);

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir la app seleccionada.')),
      );
    }
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: 'Destino de tu viaje',
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              message,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
