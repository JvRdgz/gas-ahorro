import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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
    ),
    _FuelOption(
      id: FuelOptionId.gasolina98,
      label: 'Gasolina 98',
    ),
    _FuelOption(
      id: FuelOptionId.gasoleoA,
      label: 'Gasoleo A / Diesel normal',
    ),
    _FuelOption(
      id: FuelOptionId.gasoleoPremium,
      label: 'Gasoleo Premium / Diesel premium',
    ),
    _FuelOption(
      id: FuelOptionId.gas,
      label: 'GAS / GLP / GNC',
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
  List<LatLng> _routePoints = [];
  List<Station> _routeStations = [];
  bool _hasRoute = false;
  double? _destinationLat;
  double? _destinationLng;
  bool _loadingStations = true;
  bool _isApplyingFilter = false;
  bool _filterCheapestOnly = false;
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
                Text(
                  'Escribe tu destino para recomendarte gasolineras en ruta.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.black54,
                      ),
                ),
                const SizedBox(height: 8),
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
                _FilterButton(
                  label: _filterLabel(),
                  onPressed: _openFuelFilter,
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
                    onPressed: _onRoutePressed,
                    icon: const Icon(Icons.alt_route),
                    label: const Text('Ruta'),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_isApplyingFilter)
          Positioned.fill(
            child: Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
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

  Future<void> _openFuelFilter() async {
    final result = await showModalBottomSheet<_FilterResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        FuelOptionId? tempSelection = _selectedFuel;
        bool tempCheapestOnly = _filterCheapestOnly;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                top: 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selecciona combustible',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Sin filtro'),
                        selected: tempSelection == null,
                        onSelected: (_) => setModalState(() {
                          tempSelection = null;
                        }),
                      ),
                      ..._fuelOptions.map((option) {
                        return ChoiceChip(
                          label: Text(option.label),
                          selected: tempSelection == option.id,
                          onSelected: (value) => setModalState(() {
                            tempSelection = value ? option.id : null;
                          }),
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Solo mas baratas'),
                    subtitle: const Text('Muestra solo el tramo mas economico.'),
                    value: tempCheapestOnly,
                    onChanged: (value) => setModalState(() {
                      tempCheapestOnly = value;
                    }),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(
                            _FilterResult(
                              fuel: tempSelection,
                              cheapestOnly: tempCheapestOnly,
                            ),
                          ),
                          child: const Text('Aplicar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result == null) return;
    await _applyFilter(result.fuel, result.cheapestOnly);
  }

  Future<void> _applyFilter(
    FuelOptionId? selection,
    bool cheapestOnly,
  ) async {
    setState(() {
      _isApplyingFilter = true;
      _selectedFuel = selection;
      _filterCheapestOnly = cheapestOnly;
    });
    await Future<void>.delayed(const Duration(milliseconds: 16));
    _rebuildMarkersForSelection();
    if (!mounted) return;
    setState(() {
      _isApplyingFilter = false;
    });
  }

  void _rebuildMarkersForSelection() {
    if (_stations.isEmpty) return;
    final baseStations = _hasRoute ? _routeStations : _stations;
    if (baseStations.isEmpty) {
      setState(() {
        _stationMarkers = const {};
        _minPrice = null;
        _maxPrice = null;
      });
      if (_hasRoute) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay estaciones en la ruta.')),
        );
      }
      return;
    }

    if (_selectedFuel == null) {
      setState(() {
        _stationMarkers = _buildUnselectedMarkers(baseStations);
        _minPrice = null;
        _maxPrice = null;
      });
      return;
    }

    final pricedStations = baseStations
        .map((station) {
          final price = _priceForSelectedFuel(station);
          if (price == null) return null;
          return _StationPrice(station: station, price: price);
        })
        .whereType<_StationPrice>()
        .toList();

    if (pricedStations.isEmpty) {
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

    var stationsToUse = pricedStations;
    if (_filterCheapestOnly) {
      stationsToUse = _filterCheapest(pricedStations);
      if (stationsToUse.isEmpty) {
        setState(() {
          _stationMarkers = const {};
          _minPrice = null;
          _maxPrice = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay estaciones en el rango barato.')),
        );
        return;
      }
    }

    final minPrice = stationsToUse
        .map((entry) => entry.price)
        .reduce((a, b) => a < b ? a : b);
    final maxPrice = stationsToUse
        .map((entry) => entry.price)
        .reduce((a, b) => a > b ? a : b);
    final markers = _buildMarkersForSelection(
      stationsToUse.map((entry) => entry.station).toList(),
      minPrice,
      maxPrice,
    );

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
      final normalizedPrices = <String, double>{};
      station.prices.forEach((key, value) {
        normalizedPrices[_normalizeKey(key)] = value;
      });
      final prices = <FuelOptionId, double>{};
      normalizedPrices.forEach((key, value) {
        final fuel = _classifyFuelKey(key);
        if (fuel == null) return;
        final existing = prices[fuel];
        if (existing == null || value < existing) {
          prices[fuel] = value;
        }
      });
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

  String _filterLabel() {
    final selection = _selectedFuel;
    final base = selection == null
        ? 'Selecciona combustible'
        : _fuelLabelFor(selection);
    if (_filterCheapestOnly && selection != null) {
      return '$base · mas baratas';
    }
    return base;
  }

  Color _markerColorForStation(Station station) {
    if (_selectedFuel != null && _minPrice != null && _maxPrice != null) {
      final price = _priceForSelectedFuel(station);
      if (price != null) {
        return PriceColor.colorFor(price, _minPrice!, _maxPrice!);
      }
    }
    return HSVColor.fromAHSV(1, _unselectedHue, 0.85, 0.9).toColor();
  }

  List<_StationPrice> _filterCheapest(List<_StationPrice> entries) {
    if (entries.isEmpty) return entries;
    final prices = entries.map((entry) => entry.price).toList()..sort();
    final cutoffIndex = ((prices.length - 1) * 0.25).round();
    final cutoff = prices[cutoffIndex];
    return entries.where((entry) => entry.price <= cutoff).toList();
  }

  Future<void> _applyRouteFilter(List<LatLng> routePoints) async {
    if (_stations.isEmpty) return;
    setState(() {
      _isApplyingFilter = true;
    });

    final threshold = _routeThresholdMeters(routePoints);
    final sampled = _sampleRoute(routePoints, maxPoints: 350);
    final input = <String, dynamic>{
      'stationLat':
          _stations.map((station) => station.lat).toList(growable: false),
      'stationLng':
          _stations.map((station) => station.lng).toList(growable: false),
      'routeLat': sampled.map((point) => point.latitude).toList(growable: false),
      'routeLng':
          sampled.map((point) => point.longitude).toList(growable: false),
      'thresholdMeters': threshold,
    };

    final indices = await compute(_stationsNearRoute, input);
    if (!mounted) return;
    final routeStations = indices.map((i) => _stations[i]).toList();

    setState(() {
      _routeStations = routeStations;
      _hasRoute = true;
      _isApplyingFilter = false;
    });
    _rebuildMarkersForSelection();
  }

  double _routeThresholdMeters(List<LatLng> points) {
    if (points.length < 2) return 2000;
    final length = _estimateRouteLengthMeters(points);
    if (length > 250000) return 5000;
    if (length > 100000) return 3500;
    return 2500;
  }

  double _estimateRouteLengthMeters(List<LatLng> points) {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += _distanceMeters(
        points[i - 1].latitude,
        points[i - 1].longitude,
        points[i].latitude,
        points[i].longitude,
      );
    }
    return total;
  }

  List<LatLng> _sampleRoute(List<LatLng> points, {int maxPoints = 350}) {
    if (points.length <= maxPoints) return points;
    final step = (points.length / maxPoints).ceil();
    final sampled = <LatLng>[];
    for (var i = 0; i < points.length; i += step) {
      sampled.add(points[i]);
    }
    if (sampled.last != points.last) {
      sampled.add(points.last);
    }
    return sampled;
  }

  double _distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const metersPerDegree = 111320.0;
    final avgLat = (lat1 + lat2) / 2 * 0.017453292519943295;
    final dx = (lng2 - lng1) * metersPerDegree * math.cos(avgLat);
    final dy = (lat2 - lat1) * metersPerDegree;
    return math.sqrt(dx * dx + dy * dy);
  }

  String _normalizeKey(String value) {
    final buffer = StringBuffer();
    for (final codeUnit in value.toUpperCase().codeUnits) {
      switch (codeUnit) {
        case 193: // Á
        case 192: // À
        case 194: // Â
        case 196: // Ä
          buffer.write('A');
          break;
        case 201: // É
        case 200: // È
        case 202: // Ê
        case 203: // Ë
          buffer.write('E');
          break;
        case 205: // Í
        case 204: // Ì
        case 206: // Î
        case 207: // Ï
          buffer.write('I');
          break;
        case 211: // Ó
        case 210: // Ò
        case 212: // Ô
        case 214: // Ö
          buffer.write('O');
          break;
        case 218: // Ú
        case 217: // Ù
        case 219: // Û
        case 220: // Ü
          buffer.write('U');
          break;
        case 209: // Ñ
          buffer.write('N');
          break;
        default:
          final ch = String.fromCharCode(codeUnit);
          if (RegExp(r'[A-Z0-9]').hasMatch(ch)) {
            buffer.write(ch);
          }
      }
    }
    return buffer.toString();
  }

  FuelOptionId? _classifyFuelKey(String key) {
    if (key.contains('GASOLINA95')) {
      return FuelOptionId.gasolina95;
    }
    if (key.contains('GASOLINA98')) {
      return FuelOptionId.gasolina98;
    }
    if (key.contains('GASOLEOPREMIUM') || key.contains('DIESELPREMIUM')) {
      return FuelOptionId.gasoleoPremium;
    }
    if (key.contains('GASOLEOA') || key.contains('DIESEL')) {
      return FuelOptionId.gasoleoA;
    }
    if (key.contains('GLP') ||
        key.contains('GNC') ||
        key.contains('GNL') ||
        key.contains('GASNATURAL') ||
        key.contains('GASESLICUADOSDELPETROLEO') ||
        key.contains('AUTOGAS') ||
        key.contains('BIOGASNATURAL') ||
        key.contains('GASLICUADO')) {
      return FuelOptionId.gas;
    }
    return null;
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
      _destinationLat = lat;
      _destinationLng = lng;
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
    final markerColor = _markerColorForStation(station);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => StationSheet(
        station: station,
        markerColor: markerColor,
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
        _routePoints = polylinePoints;
        _hasRoute = polylinePoints.isNotEmpty;
      });

      if (polylinePoints.isNotEmpty) {
        await _applyRouteFilter(polylinePoints);
        final bounds = _boundsFromLatLng(polylinePoints);
        await _mapController?.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 48),
        );
      } else {
        setState(() {
          _routeStations = [];
          _hasRoute = false;
        });
        _rebuildMarkersForSelection();
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

  Future<void> _onRoutePressed() async {
    final lat = _destinationLat;
    final lng = _destinationLng;
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un destino primero.')),
      );
      return;
    }
    await _drawRouteToDestination(lat, lng);
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
          hintText: 'Ir a',
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
  });

  final FuelOptionId id;
  final String label;
}

class _FilterResult {
  const _FilterResult({
    required this.fuel,
    required this.cheapestOnly,
  });

  final FuelOptionId? fuel;
  final bool cheapestOnly;
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.filter_alt),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class _StationPrice {
  const _StationPrice({
    required this.station,
    required this.price,
  });

  final Station station;
  final double price;
}

List<int> _stationsNearRoute(Map<String, dynamic> input) {
  const metersPerDegree = 111320.0;
  const degToRad = 0.017453292519943295;

  final stationLat = (input['stationLat'] as List).cast<double>();
  final stationLng = (input['stationLng'] as List).cast<double>();
  final routeLat = (input['routeLat'] as List).cast<double>();
  final routeLng = (input['routeLng'] as List).cast<double>();
  final threshold = (input['thresholdMeters'] as num).toDouble();
  final thresholdSq = threshold * threshold;

  if (routeLat.length < 2) return [];

  final indices = <int>[];
  for (var i = 0; i < stationLat.length; i++) {
    final lat = stationLat[i];
    final lng = stationLng[i];
    var within = false;

    for (var j = 1; j < routeLat.length; j++) {
      final lat1 = routeLat[j - 1];
      final lng1 = routeLng[j - 1];
      final lat2 = routeLat[j];
      final lng2 = routeLng[j];
      final avgLat = (lat1 + lat2) / 2 * degToRad;
      final cosLat = math.cos(avgLat);

      final dx = (lng2 - lng1) * metersPerDegree * cosLat;
      final dy = (lat2 - lat1) * metersPerDegree;
      final px = (lng - lng1) * metersPerDegree * cosLat;
      final py = (lat - lat1) * metersPerDegree;

      final segLen2 = dx * dx + dy * dy;
      double distSq;
      if (segLen2 == 0) {
        distSq = px * px + py * py;
      } else {
        var t = (px * dx + py * dy) / segLen2;
        if (t < 0) t = 0;
        if (t > 1) t = 1;
        final projx = t * dx;
        final projy = t * dy;
        final diffx = px - projx;
        final diffy = py - projy;
        distSq = diffx * diffx + diffy * diffy;
      }

      if (distSq <= thresholdSq) {
        within = true;
        break;
      }
    }

    if (within) {
      indices.add(i);
    }
  }
  return indices;
}
