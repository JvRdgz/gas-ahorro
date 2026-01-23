import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:uuid/uuid.dart';

import 'models/place_prediction.dart';
import 'models/station.dart';
import 'services/directions_api.dart';
import 'services/fuel_api.dart';
import 'services/navigation_launcher.dart';
import 'services/places_api.dart';
import 'services/sun_times_api.dart';
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
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B6E4F),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  static const double _unselectedHue = BitmapDescriptor.hueAzure;

  static const List<_FuelOption> _fuelOptions = [
    _FuelOption(
      id: FuelOptionId.gasolina95,
      label: 'Gasolina 95',
      keys: ['Gasolina 95 E5', 'Gasolina 95 E5 Premium'],
    ),
    _FuelOption(
      id: FuelOptionId.gasolina98,
      label: 'Gasolina 98',
      keys: ['Gasolina 98 E5', 'Gasolina 98 E5 Premium'],
    ),
    _FuelOption(
      id: FuelOptionId.gasoleoA,
      label: 'Gasoleo A / Diesel normal',
      keys: ['Gasoleo A'],
    ),
    _FuelOption(
      id: FuelOptionId.gasoleoPremium,
      label: 'Gasoleo Premium / Diesel premium',
      keys: ['Gasoleo Premium'],
    ),
    _FuelOption(
      id: FuelOptionId.gas,
      label: 'GAS / GLP / GNC',
      keys: ['GLP', 'GNC', 'GNL'],
    ),
  ];

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _fuelApi = FuelApi();
  final _launcher = NavigationLauncher();
  final _placesApi = PlacesApi();
  final _sunTimesApi = SunTimesApi();
  final _directionsApi = DirectionsApi();
  final _uuid = const Uuid();

  GoogleMapController? _mapController;
  Timer? _debounce;
  Timer? _nightTimer;
  String _sessionToken = '';
  List<PlacePrediction> _predictions = [];
  bool _loadingPredictions = false;
  String? _darkMapStyle;
  bool? _isNightByLocation;
  double? _lastLat;
  double? _lastLng;
  Position? _currentPosition;
  Set<Polyline> _routePolylines = {};
  bool _loadingStations = true;
  String? _stationsError;
  String? _stationsErrorDetails;
  List<Station> _stations = [];
  final Map<String, Map<FuelOptionId, double>> _stationFuelPrices = {};
  double? _minPrice;
  double? _maxPrice;
  Set<Marker> _stationMarkers = const {};
  FuelOptionId? _selectedFuel;
  final Map<double, BitmapDescriptor> _iconCache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStations();
    _sessionToken = _uuid.v4();
    _loadMapStyle();
    _initLocationAndNightMode();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    _nightTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    _applyMapStyle();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loadingStations) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_stationsError != null) {
      return _ErrorState(
        message: _stationsError!,
        details: _stationsErrorDetails,
        onRetry: _loadStations,
      );
    }

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(_stations.first.lat, _stations.first.lng),
            zoom: 6,
          ),
          onMapCreated: (controller) {
            _mapController = controller;
            _applyMapStyle();
          },
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          markers: _stationMarkers,
          polylines: _routePolylines,
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SearchBar(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onChanged: _onSearchChanged,
                ),
                if (_searchFocusNode.hasFocus &&
                    (_predictions.isNotEmpty || _loadingPredictions))
                  _PredictionsList(
                    isLoading: _loadingPredictions,
                    predictions: _predictions,
                    onSelected: _onPredictionSelected,
                  ),
                const SizedBox(height: 10),
                _FuelSelector(
                  selected: _selectedFuel,
                  options: _fuelOptions,
                  onChanged: _onFuelSelected,
                ),
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
        if (_selectedFuel != null && _minPrice != null && _maxPrice != null)
          Positioned(
            left: 16,
            bottom: 24,
            child: PriceLegend(
              minPrice: _minPrice!,
              maxPrice: _maxPrice!,
              label: _fuelLabelFor(_selectedFuel),
            ),
          ),
        Positioned.fill(
          child: SafeArea(
            minimum: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.bottomRight,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FloatingActionButton(
                    heroTag: 'fab-location',
                    onPressed: _centerOnUser,
                    child: const Icon(Icons.my_location),
                  ),
                  const SizedBox(height: 12),
                  FloatingActionButton.extended(
                    heroTag: 'fab-route',
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Pendiente de integrar ruta y geocodificacion.',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.alt_route),
                    label: const Text('Ruta'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _loadStations() async {
    setState(() {
      _loadingStations = true;
      _stationsError = null;
      _stationsErrorDetails = null;
    });

    try {
      final stations = await _fuelApi.fetchStations();
      if (!mounted) return;

      if (stations.isEmpty) {
        setState(() {
          _loadingStations = false;
          _stationsError = 'No hay estaciones disponibles.';
          _stationsErrorDetails = 'Respuesta vacía del servicio.';
        });
        return;
      }

      final markers = _buildUnselectedMarkers(stations);

      setState(() {
        _stations = stations;
        _stationFuelPrices
          ..clear()
          ..addAll(_buildFuelPriceIndex(stations));
        _minPrice = null;
        _maxPrice = null;
        _stationMarkers = markers;
        _loadingStations = false;
      });
      if (_selectedFuel != null) {
        _rebuildMarkersForSelection();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingStations = false;
        _stationsError = 'No se pudo cargar la informacion.';
        _stationsErrorDetails = error.toString();
      });
    }
  }

  Set<Marker> _buildUnselectedMarkers(List<Station> stations) {
    return stations.map((station) {
      return Marker(
        markerId: MarkerId(station.id),
        position: LatLng(station.lat, station.lng),
        icon: _iconForHue(_unselectedHue),
        onTap: () => _showStationSheet(station),
      );
    }).toSet();
  }

  Set<Marker> _buildMarkersForSelection(
    List<Station> stations,
    double minPrice,
    double maxPrice,
  ) {
    return stations.map((station) {
      final price = _priceForSelectedFuel(station);
      if (price == null) return null;
      final hue = PriceColor.hueFor(price, minPrice, maxPrice);
      return Marker(
        markerId: MarkerId(station.id),
        position: LatLng(station.lat, station.lng),
        icon: _iconForHue(hue),
        onTap: () => _showStationSheet(station),
      );
    }).whereType<Marker>().toSet();
  }

  double? _priceForSelectedFuel(Station station) {
    final selected = _selectedFuel;
    if (selected == null) return null;
    final price = _stationFuelPrices[station.id]?[selected];
    return price;
  }

  void _onFuelSelected(FuelOptionId? selection) {
    setState(() {
      _selectedFuel = selection;
    });
    _rebuildMarkersForSelection();
  }

  void _rebuildMarkersForSelection() {
    if (_stations.isEmpty) return;
    if (_selectedFuel == null) {
      setState(() {
        _stationMarkers = _buildUnselectedMarkers(_stations);
        _minPrice = null;
        _maxPrice = null;
      });
      return;
    }

    final prices = _stations
        .map(_priceForSelectedFuel)
        .whereType<double>()
        .toList();

    if (prices.isEmpty) {
      setState(() {
        _stationMarkers = const {};
        _minPrice = null;
        _maxPrice = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay estaciones con ese combustible.')),
      );
      return;
    }

    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final maxPrice = prices.reduce((a, b) => a > b ? a : b);
    final markers = _buildMarkersForSelection(_stations, minPrice, maxPrice);

    setState(() {
      _minPrice = minPrice;
      _maxPrice = maxPrice;
      _stationMarkers = markers;
    });
  }

  Map<String, Map<FuelOptionId, double>> _buildFuelPriceIndex(
    List<Station> stations,
  ) {
    final index = <String, Map<FuelOptionId, double>>{};
    for (final station in stations) {
      final prices = <FuelOptionId, double>{};
      for (final option in _fuelOptions) {
        final values = option.keys
            .map((key) => station.prices[key])
            .whereType<double>()
            .toList();
        if (values.isNotEmpty) {
          prices[option.id] = values.reduce((a, b) => a < b ? a : b);
        }
      }
      index[station.id] = prices;
    }
    return index;
  }

  BitmapDescriptor _iconForHue(double hue) {
    final bucketed = (hue / 5).round() * 5.0;
    return _iconCache.putIfAbsent(
      bucketed,
      () => BitmapDescriptor.defaultMarkerWithHue(bucketed),
    );
  }

  String _fuelLabelFor(FuelOptionId? selection) {
    if (selection == null) return '';
    return _fuelOptions
        .firstWhere((option) => option.id == selection)
        .label;
  }

  Future<void> _loadMapStyle() async {
    try {
      _darkMapStyle = await rootBundle.loadString(
        'assets/map_style_dark.json',
      );
      _applyMapStyle();
    } catch (_) {
      // Silently ignore style loading failures.
    }
  }

  void _applyMapStyle() {
    final controller = _mapController;
    if (controller == null) return;
    final isDark = _isNightByLocation ??
        (WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark);
    controller.setMapStyle(isDark ? _darkMapStyle : null);
  }

  Future<void> _initLocationAndNightMode() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.low,
    );
    _currentPosition = position;
    _lastLat = position.latitude;
    _lastLng = position.longitude;
    await _refreshNightMode(position.latitude, position.longitude);

    _nightTimer?.cancel();
    _nightTimer = Timer.periodic(const Duration(minutes: 20), (_) async {
      if (_lastLat == null || _lastLng == null) return;
      await _refreshNightMode(_lastLat!, _lastLng!);
    });
  }

  Future<void> _refreshNightMode(double lat, double lng) async {
    final isNight = await _sunTimesApi.isNight(lat: lat, lng: lng);
    if (!mounted || isNight == null) return;
    setState(() {
      _isNightByLocation = isNight;
    });
    _applyMapStyle();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      if (value.trim().length < 3) {
        setState(() {
          _predictions = [];
          _loadingPredictions = false;
        });
        return;
      }
      _fetchPredictions(value.trim());
    });
  }

  Future<void> _fetchPredictions(String input) async {
    setState(() => _loadingPredictions = true);
    try {
      final results = await _placesApi.autocomplete(
        input: input,
        sessionToken: _sessionToken,
      );
      if (!mounted) return;
      setState(() {
        _predictions = results;
        _loadingPredictions = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _predictions = [];
        _loadingPredictions = false;
      });
    }
  }

  Future<void> _onPredictionSelected(PlacePrediction prediction) async {
    _searchController.text = prediction.description;
    _searchController.selection = TextSelection.collapsed(
      offset: _searchController.text.length,
    );
    FocusScope.of(context).unfocus();
    setState(() {
      _predictions = [];
    });

    try {
      final location = await _placesApi.fetchPlaceLocation(
        placeId: prediction.placeId,
        sessionToken: _sessionToken,
      );
      _sessionToken = _uuid.v4();
      final lat = location['lat']!;
      final lng = location['lng']!;
      await _drawRouteToDestination(lat, lng);
      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(lat, lng), 11),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo obtener la ubicación.')),
      );
    }
  }

  void _showStationSheet(Station station) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => StationSheet(
        station: station,
        onNavigate: () => _openDefaultNavigation(station),
      ),
    );
  }

  Future<void> _drawRouteToDestination(double destLat, double destLng) async {
    final current = _currentPosition;
    if (current == null) return;

    try {
      final points = await _directionsApi.fetchRoute(
        originLat: current.latitude,
        originLng: current.longitude,
        destLat: destLat,
        destLng: destLng,
      );
      if (!mounted) return;

      final polylinePoints = points
          .map((point) => LatLng(point['lat']!, point['lng']!))
          .toList();
      setState(() {
        _routePolylines = {
          Polyline(
            polylineId: const PolylineId('route'),
            color: const Color(0xFF0B6E4F),
            width: 5,
            points: polylinePoints,
          ),
        };
      });

      if (polylinePoints.isNotEmpty) {
        final bounds = _boundsFromLatLng(polylinePoints);
        await _mapController?.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 48),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo calcular la ruta.')),
      );
    }
  }

  LatLngBounds _boundsFromLatLng(List<LatLng> points) {
    double? minLat, maxLat, minLng, maxLng;
    for (final point in points) {
      minLat = minLat == null ? point.latitude : minLat < point.latitude ? minLat : point.latitude;
      maxLat = maxLat == null ? point.latitude : maxLat > point.latitude ? maxLat : point.latitude;
      minLng = minLng == null ? point.longitude : minLng < point.longitude ? minLng : point.longitude;
      maxLng = maxLng == null ? point.longitude : maxLng > point.longitude ? maxLng : point.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat ?? 0, minLng ?? 0),
      northeast: LatLng(maxLat ?? 0, maxLng ?? 0),
    );
  }

  Future<void> _openDefaultNavigation(Station station) async {
    final lat = station.lat;
    final lng = station.lng;
    final ok = await _launcher.openDefaultMaps(lat, lng);

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir la app seleccionada.')),
      );
    }
  }

  Future<void> _centerOnUser() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Activa los servicios de ubicación.')),
      );
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permiso de ubicación denegado.')),
      );
      return;
    }

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    _currentPosition = position;
    _lastLat = position.latitude;
    _lastLng = position.longitude;
    await _refreshNightMode(position.latitude, position.longitude);
    await _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(position.latitude, position.longitude),
        13,
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

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
        focusNode: focusNode,
        onChanged: onChanged,
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

class _PredictionsList extends StatelessWidget {
  const _PredictionsList({
    required this.isLoading,
    required this.predictions,
    required this.onSelected,
  });

  final bool isLoading;
  final List<PlacePrediction> predictions;
  final ValueChanged<PlacePrediction> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
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
      constraints: const BoxConstraints(maxHeight: 240),
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
                  leading: const Icon(Icons.place),
                  title: Text(prediction.primaryText),
                  subtitle: prediction.secondaryText.isEmpty
                      ? null
                      : Text(prediction.secondaryText),
                  onTap: () => onSelected(prediction),
                );
              },
            ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
    this.details,
  });

  final String message;
  final VoidCallback onRetry;
  final String? details;

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
            if (details != null) ...[
              const SizedBox(height: 8),
              Text(
                details!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.redAccent,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
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

enum FuelOptionId {
  gasolina95,
  gasolina98,
  gasoleoA,
  gasoleoPremium,
  gas,
}

class _FuelOption {
  const _FuelOption({
    required this.id,
    required this.label,
    required this.keys,
  });

  final FuelOptionId id;
  final String label;
  final List<String> keys;
}

class _FuelSelector extends StatelessWidget {
  const _FuelSelector({
    required this.selected,
    required this.options,
    required this.onChanged,
  });

  final FuelOptionId? selected;
  final List<_FuelOption> options;
  final ValueChanged<FuelOptionId?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
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
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: const Text('Todos'),
            selected: selected == null,
            onSelected: (_) => onChanged(null),
          ),
          ...options.map((option) {
            return ChoiceChip(
              label: Text(option.label),
              selected: selected == option.id,
              onSelected: (value) =>
                  onChanged(value ? option.id : null),
            );
          }),
        ],
      ),
    );
  }
}
