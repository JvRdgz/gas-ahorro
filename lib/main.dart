import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  static const Color _brandGreenDark = Color(0xFF0B6E4F);
  static const Color _brandGreenLight = Color(0xFF57D39D);
  static const int _iosViewportThreshold = 1500;
  static const int _viewportFilterThreshold = 700;
  static const int _downsampleThreshold = 500;

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
  final _mapKey = GlobalKey();
  final _searchKey = GlobalKey();
  final _filterKey = GlobalKey();
  final _routeKey = GlobalKey();

  GoogleMapController? _mapController;
  List<Station> _markerStationsSource = const [];
  double? _markerMinPrice;
  double? _markerMaxPrice;
  Timer? _debounce;
  Timer? _nightTimer;
  String _sessionToken = '';
  List<PlacePrediction> _predictions = [];
  bool _loadingPredictions = false;
  int _autocompleteRequestId = 0;
  String? _darkMapStyle;
  bool? _isNightByLocation;
  double? _lastLat;
  double? _lastLng;
  Position? _currentPosition;
  Set<Polyline> _routePolylines = {};
  List<Station> _routeStations = [];
  bool _hasRoute = false;
  List<LatLng> _routePoints = [];
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
  final Map<double, Future<BitmapDescriptor>> _iconLoaders = {};
  final Map<String, BitmapDescriptor> _priceIconCache = {};
  final Map<String, Future<BitmapDescriptor>> _priceIconLoaders = {};
  bool _showTutorial = false;
  int _tutorialStepIndex = 0;
  late final List<_TutorialStep> _tutorialSteps = [
    _TutorialStep(
      title: 'Busca tu destino',
      description:
          'Escribe un lugar y elige una sugerencia para trazar la ruta.',
      targetKey: _searchKey,
    ),
    _TutorialStep(
      title: 'Ver la ruta',
      description:
          'La ruta se mostrará en el mapa con las gasolineras que estén de camino.',
      targetKey: _routeKey,
    ),
    _TutorialStep(
      title: 'Filtra combustible',
      description:
          'Selecciona el tipo de combustible y activa “Solo más baratas” si '
          'quieres ver únicamente las mejores opciones.',
      targetKey: _filterKey,
    ),
    _TutorialStep(
      title: 'Toca una gasolinera',
      description:
          'Pulsa un surtidor para ver los detalles y precios disponibles.',
      targetKey: _mapKey,
    ),
    _TutorialStep(
      title: 'Precio en el mapa',
      description:
          'El precio del combustible seleccionado aparece junto al icono '
          'para comparar de un vistazo.',
      targetKey: _mapKey,
    ),
    _TutorialStep(
      title: 'Navegar con “Ir”',
      description:
          'Al abrir una gasolinera, el botón “Ir” abre tu app de navegación '
          'por defecto y crea la ruta con esa parada.',
      targetKey: _mapKey,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStations();
    _sessionToken = _uuid.v4();
    _loadMapStyle();
    _initLocationAndNightMode();
    _maybeShowTutorial();
  }

  Future<void> _maybeShowTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('onboarding_seen') ?? false;
    if (seen || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _showTutorial = true;
        _tutorialStepIndex = 0;
      });
    });
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

    final media = MediaQuery.of(context);
    final viewPadding = media.padding;
    final maxSuggestionsHeight = math.max(
      120.0,
      math.min(
        240.0,
        media.size.height - media.viewInsets.bottom - viewPadding.top - 220,
      ),
    );

    return Stack(
      children: [
        KeyedSubtree(
          key: _mapKey,
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(_stations.first.lat, _stations.first.lng),
              zoom: 6,
            ),
            padding: EdgeInsets.only(
              top: viewPadding.top,
              bottom: viewPadding.bottom + 12,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              _applyMapStyle();
              if (_markerStationsSource.isNotEmpty) {
                _refreshVisibleMarkers();
              }
            },
            onCameraIdle: _onCameraIdle,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            markers: _stationMarkers,
            polylines: _routePolylines,
          ),
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
                        color: _palette.textSecondary,
                      ),
                ),
                const SizedBox(height: 8),
                _SearchBar(
                  key: _searchKey,
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onChanged: _onSearchChanged,
                  onSubmitted: _onSearchSubmitted,
                  onClear: _clearRouteAndSearch,
                  hasRoute: _hasRoute,
                  palette: _palette,
                ),
                if (_searchFocusNode.hasFocus &&
                    (_predictions.isNotEmpty || _loadingPredictions))
                  _PredictionsList(
                    isLoading: _loadingPredictions,
                    predictions: _predictions,
                    onSelected: _onPredictionSelected,
                    palette: _palette,
                    maxHeight: maxSuggestionsHeight,
                  ),
                const SizedBox(height: 10),
                _FilterButton(
                  key: _filterKey,
                  label: _filterLabel(),
                  onPressed: _openFuelFilter,
                  palette: _palette,
                ),
              ],
            ),
          ),
        ),
        if (_selectedFuel != null && _minPrice != null && _maxPrice != null)
          Positioned(
            left: 16,
            bottom: 24 + viewPadding.bottom,
            child: PriceLegend(
              minPrice: _minPrice!,
              maxPrice: _maxPrice!,
              label: _fuelLabelFor(_selectedFuel),
              backgroundColor: _palette.isDark
                  ? _palette.surface.withOpacity(0.95)
                  : _palette.surfaceAlt,
              textColor: _palette.textPrimary,
              secondaryTextColor: _palette.textSecondary,
              shadowColor: _palette.shadow,
              borderColor: _palette.border,
            ),
          ),
        Positioned(
          right: 16,
          bottom: viewPadding.bottom + 140,
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
                key: _routeKey,
                icon: const Icon(Icons.alt_route),
                label: const Text('Ruta'),
              ),
            ],
          ),
        ),
        if (_isApplyingFilter)
          Positioned.fill(
            child: Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
        if (_showTutorial)
          _TutorialOverlay(
            step: _tutorialSteps[_tutorialStepIndex],
            stepIndex: _tutorialStepIndex,
            totalSteps: _tutorialSteps.length,
            targetRect:
                _rectForKey(_tutorialSteps[_tutorialStepIndex].targetKey),
            onSkip: _endTutorial,
            onNext: _nextTutorialStep,
          ),
      ],
    );
  }

  Rect? _rectForKey(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return null;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final offset = renderObject.localToGlobal(Offset.zero);
    return offset & renderObject.size;
  }

  Future<void> _endTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);
    if (!mounted) return;
    setState(() {
      _showTutorial = false;
    });
  }

  void _nextTutorialStep() {
    final isLast = _tutorialStepIndex >= _tutorialSteps.length - 1;
    if (isLast) {
      _endTutorial();
      return;
    }
    setState(() {
      _tutorialStepIndex += 1;
    });
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

      setState(() {
        _stations = stations;
        _stationFuelPrices
          ..clear()
          ..addAll(_buildFuelPriceIndex(stations));
        _minPrice = null;
        _maxPrice = null;
        _stationMarkers = const {};
        _loadingStations = true;
      });
      if (_selectedFuel != null) {
        await _rebuildMarkersForSelection();
      } else {
        await _setMarkersForStations(stations);
      }
      if (!mounted) return;
      setState(() {
        _loadingStations = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingStations = false;
        _stationsError = 'No se pudo cargar la informacion.';
        _stationsErrorDetails = error.toString();
      });
    }
  }

  Future<Set<Marker>> _buildUnselectedMarkers(
    List<Station> stations,
  ) async {
    final icon = await _iconForHue(_unselectedHue);
    return stations.map((station) {
      return Marker(
        markerId: MarkerId(station.id),
        position: LatLng(station.lat, station.lng),
        icon: icon,
        onTap: () => _showStationSheet(station),
      );
    }).toSet();
  }

  Future<Set<Marker>> _buildMarkersForSelection(
    List<Station> stations,
    double minPrice,
    double maxPrice,
  ) async {
    final iconKeys = <_PriceIconKey>{};
    final stationIcons = <String, _PriceIconKey>{};
    for (final station in stations) {
      final price = _priceForSelectedFuel(station);
      if (price == null) continue;
      final hue = _bucketHue(PriceColor.hueFor(price, minPrice, maxPrice));
      final label = _formatPrice(price);
      final key = _PriceIconKey(hue, label);
      iconKeys.add(key);
      stationIcons[station.id] = key;
    }
    await Future.wait(
      iconKeys.map((key) => _iconForHueWithPrice(key.hue, key.label)),
    );
    return stations.map((station) {
      final key = stationIcons[station.id];
      if (key == null) return null;
      final icon = _priceIconCache[_priceCacheKey(key.hue, key.label)];
      if (icon == null) return null;
      return Marker(
        markerId: MarkerId(station.id),
        position: LatLng(station.lat, station.lng),
        icon: icon,
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
    final palette = _palette;
    final result = await showModalBottomSheet<_FilterResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: palette.surface,
      builder: (context) {
        FuelOptionId? tempSelection = _selectedFuel;
        bool tempCheapestOnly = _filterCheapestOnly;
        return StatefulBuilder(
          builder: (context, setModalState) {
            final media = MediaQuery.of(context);
            final bottomInset =
                16 + media.viewInsets.bottom + media.viewPadding.bottom;
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: bottomInset,
                top: 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selecciona combustible',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: palette.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(
                          'Sin filtro',
                          style: TextStyle(color: palette.textPrimary),
                        ),
                        selected: tempSelection == null,
                        selectedColor: palette.isDark
                            ? palette.accent.withOpacity(0.35)
                            : const Color(0xFFE6F4EE),
                        backgroundColor: palette.surfaceAlt,
                        checkmarkColor:
                            palette.isDark ? Colors.black87 : palette.accent,
                        side: BorderSide(color: palette.border),
                        onSelected: (_) => setModalState(() {
                          tempSelection = null;
                        }),
                      ),
                      ..._fuelOptions.map((option) {
                        return ChoiceChip(
                          label: Text(
                            option.label,
                            style: TextStyle(color: palette.textPrimary),
                          ),
                          selected: tempSelection == option.id,
                          selectedColor: palette.isDark
                              ? palette.accent.withOpacity(0.35)
                              : const Color(0xFFE6F4EE),
                          backgroundColor: palette.surfaceAlt,
                          checkmarkColor:
                              palette.isDark ? Colors.black87 : palette.accent,
                          side: BorderSide(color: palette.border),
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
                    title: Text(
                      'Solo mas baratas',
                      style: TextStyle(color: palette.textPrimary),
                    ),
                    subtitle: Text(
                      'Muestra solo el tramo mas economico.',
                      style: TextStyle(color: palette.textSecondary),
                    ),
                    value: tempCheapestOnly,
                    activeColor: palette.accent,
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
                          style: OutlinedButton.styleFrom(
                            foregroundColor: palette.textPrimary,
                            side: BorderSide(color: palette.border),
                          ),
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
                          style: FilledButton.styleFrom(
                            backgroundColor: palette.accent,
                            foregroundColor:
                                palette.isDark ? Colors.black87 : Colors.white,
                          ),
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
      _selectedFuel = selection;
      _filterCheapestOnly = cheapestOnly;
    });
    await _runWithFilterLoading(_rebuildMarkersForSelection);
  }

  Future<void> _rebuildMarkersForSelection() async {
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
        _minPrice = null;
        _maxPrice = null;
      });
      await _setMarkersForStations(baseStations);
      return;
    }

    final entries = <Map<String, dynamic>>[];
    for (var i = 0; i < baseStations.length; i++) {
      final station = baseStations[i];
      final price = _priceForSelectedFuel(station);
      if (price == null) continue;
      entries.add({
        'index': i,
        'price': price,
      });
    }

    if (entries.isEmpty) {
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

    final result = await compute(_filterStationsForSelection, {
      'entries': entries,
      'filterCheapestOnly': _filterCheapestOnly,
    });
    if (!mounted) return;
    final indices = (result['indices'] as List).cast<int>();
    if (indices.isEmpty) {
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
    final minPrice = (result['minPrice'] as num).toDouble();
    final maxPrice = (result['maxPrice'] as num).toDouble();
    final stationsToUse = indices.map((i) => baseStations[i]).toList();
    await _setMarkersForStations(
      stationsToUse,
      minPrice: minPrice,
      maxPrice: maxPrice,
    );

    setState(() {
      _minPrice = minPrice;
      _maxPrice = maxPrice;
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

  Future<void> _setMarkersInBatches(Iterable<Marker> markers) async {
    const batchSize = 400;
    final list = markers.toList(growable: false);
    final result = <Marker>{};
    for (var i = 0; i < list.length; i += batchSize) {
      final end = math.min(i + batchSize, list.length);
      result.addAll(list.sublist(i, end));
      if (!mounted) return;
      setState(() {
        _stationMarkers = Set<Marker>.of(result);
      });
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<void> _setMarkersForStations(
    List<Station> stations, {
    double? minPrice,
    double? maxPrice,
  }) async {
    _markerStationsSource = stations;
    _markerMinPrice = minPrice;
    _markerMaxPrice = maxPrice;
    await _refreshVisibleMarkers();
  }

  void _onCameraIdle() {
    if (!mounted || _markerStationsSource.isEmpty) return;
    _refreshVisibleMarkers();
  }

  Future<void> _refreshVisibleMarkers() async {
    final controller = _mapController;
    if (!mounted) return;
    if (controller == null) return;

    var stationsToRender = _markerStationsSource;
    final bounds = await controller.getVisibleRegion();
    final zoom = await controller.getZoomLevel();
    if (stationsToRender.length > _viewportFilterThreshold ||
        (defaultTargetPlatform == TargetPlatform.iOS &&
            stationsToRender.length > _iosViewportThreshold)) {
      final paddedBounds = _expandBounds(bounds, 0.2);
      stationsToRender = _stationsInBounds(stationsToRender, paddedBounds);
    }

    stationsToRender = _downsampleForZoom(stationsToRender, zoom, bounds);

    final minPrice = _markerMinPrice;
    final maxPrice = _markerMaxPrice;
    final markers = (minPrice != null && maxPrice != null)
        ? await _buildMarkersForSelection(stationsToRender, minPrice, maxPrice)
        : await _buildUnselectedMarkers(stationsToRender);
    await _setMarkersInBatches(markers);
  }

  LatLngBounds _expandBounds(LatLngBounds bounds, double factor) {
    final latSpan = bounds.northeast.latitude - bounds.southwest.latitude;
    final lngSpan = bounds.northeast.longitude - bounds.southwest.longitude;
    final latPad = latSpan * factor;
    final lngPad = lngSpan * factor;
    return LatLngBounds(
      southwest: LatLng(
        bounds.southwest.latitude - latPad,
        bounds.southwest.longitude - lngPad,
      ),
      northeast: LatLng(
        bounds.northeast.latitude + latPad,
        bounds.northeast.longitude + lngPad,
      ),
    );
  }

  List<Station> _stationsInBounds(
    List<Station> stations,
    LatLngBounds bounds,
  ) {
    return stations.where((station) {
      final lat = station.lat;
      final lng = station.lng;
      return lat <= bounds.northeast.latitude &&
          lat >= bounds.southwest.latitude &&
          lng <= bounds.northeast.longitude &&
          lng >= bounds.southwest.longitude;
    }).toList(growable: false);
  }

  List<Station> _downsampleForZoom(
    List<Station> stations,
    double zoom,
    LatLngBounds bounds,
  ) {
    final cellSizeMeters = _cellSizeMetersForZoom(zoom);
    if (cellSizeMeters <= 0 || stations.length <= _downsampleThreshold) {
      return stations;
    }

    final midLat = (bounds.northeast.latitude + bounds.southwest.latitude) / 2;
    final metersPerDegreeLat = 111320.0;
    final metersPerDegreeLng =
        math.max(1e-6, 111320.0 * math.cos(midLat * math.pi / 180));
    final cellLat = cellSizeMeters / metersPerDegreeLat;
    final cellLng = cellSizeMeters / metersPerDegreeLng;

    final preferCheapest = _selectedFuel != null;
    final buckets = <String, Station>{};
    final bucketPrice = <String, double>{};

    for (final station in stations) {
      final key =
          '${(station.lat / cellLat).floor()}_${(station.lng / cellLng).floor()}';
      if (!preferCheapest) {
        buckets.putIfAbsent(key, () => station);
        continue;
      }
      final price = _priceForSelectedFuel(station);
      if (price == null) continue;
      final existing = bucketPrice[key];
      if (existing == null || price < existing) {
        buckets[key] = station;
        bucketPrice[key] = price;
      }
    }

    if (buckets.isEmpty) {
      return stations;
    }
    return buckets.values.toList(growable: false);
  }

  double _cellSizeMetersForZoom(double zoom) {
    if (zoom < 6) return 45000;
    if (zoom < 7) return 30000;
    if (zoom < 8) return 20000;
    if (zoom < 9) return 12000;
    if (zoom < 10) return 8000;
    if (zoom < 11) return 5000;
    if (zoom < 12) return 2500;
    if (zoom < 13) return 1500;
    if (zoom < 14) return 900;
    if (zoom < 15) return 500;
    return 0;
  }

  Future<void> _runWithFilterLoading(Future<void> Function() action) async {
    if (!mounted) return;
    setState(() {
      _isApplyingFilter = true;
    });
    await Future<void>.delayed(Duration.zero);
    await WidgetsBinding.instance.endOfFrame;

    final stopwatch = Stopwatch()..start();
    await action();
    if (!mounted) return;

    final remaining = 300 - stopwatch.elapsedMilliseconds;
    if (remaining > 0) {
      await Future<void>.delayed(Duration(milliseconds: remaining));
    }
    if (!mounted) return;
    setState(() {
      _isApplyingFilter = false;
    });
  }

  double _bucketHue(double hue) {
    return (hue / 10).round() * 10.0;
  }

  String _formatPrice(double price) {
    return '${price.toStringAsFixed(3).replaceAll('.', ',')} €';
  }

  String _priceCacheKey(double hue, String label) {
    return '${hue.toStringAsFixed(0)}|$label';
  }

  Future<BitmapDescriptor> _iconForHue(double hue) async {
    final bucketed = _bucketHue(hue);
    final cached = _iconCache[bucketed];
    if (cached != null) return cached;
    final pending = _iconLoaders[bucketed];
    if (pending != null) return pending;
    final future = _buildGasMarkerIcon(_colorForHue(bucketed));
    _iconLoaders[bucketed] = future;
    final icon = await future;
    _iconCache[bucketed] = icon;
    _iconLoaders.remove(bucketed);
    return icon;
  }

  Future<BitmapDescriptor> _iconForHueWithPrice(
    double hue,
    String label,
  ) async {
    final bucketed = _bucketHue(hue);
    final key = _priceCacheKey(bucketed, label);
    final cached = _priceIconCache[key];
    if (cached != null) return cached;
    final pending = _priceIconLoaders[key];
    if (pending != null) return pending;
    final future = _buildGasMarkerIconWithPrice(
      _colorForHue(bucketed),
      label,
    );
    _priceIconLoaders[key] = future;
    final icon = await future;
    _priceIconCache[key] = icon;
    _priceIconLoaders.remove(key);
    return icon;
  }

  Color _colorForHue(double hue) {
    return HSVColor.fromAHSV(1, hue, 0.85, 0.9).toColor();
  }

  Future<BitmapDescriptor> _buildGasMarkerIcon(Color color) async {
    const circleSize = 84.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = const Offset(circleSize / 2, circleSize / 2);
    final radius = circleSize / 2;

    final paint = Paint()..color = color;
    canvas.drawCircle(center, radius, paint);

    const icon = Icons.local_gas_station;
    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 42,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final offset = Offset(
      center.dx - textPainter.width / 2,
      center.dy - textPainter.height / 2,
    );
    textPainter.paint(canvas, offset);

    final image = await recorder
        .endRecording()
        .toImage(circleSize.toInt(), circleSize.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  Future<BitmapDescriptor> _buildGasMarkerIconWithPrice(
    Color color,
    String label,
  ) async {
    const circleSize = 88.0;
    const pillHeight = 52.0;
    const pillRadius = 22.0;
    const textSize = 34.0;
    const pillPadding = 20.0;
    const gap = 14.0;

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: textSize,
          fontWeight: FontWeight.w600,
          color: Color(0xFF163027),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final pillWidth = textPainter.width + pillPadding * 2;
    final width = circleSize + gap + pillWidth;
    final height = circleSize;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = const Offset(circleSize / 2, circleSize / 2);
    final radius = circleSize / 2;

    final paint = Paint()..color = color;
    canvas.drawCircle(center, radius, paint);

    const icon = Icons.local_gas_station;
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 52,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final iconOffset = Offset(
      center.dx - iconPainter.width / 2,
      center.dy - iconPainter.height / 2,
    );
    iconPainter.paint(canvas, iconOffset);

    final pillLeft = circleSize - 6;
    final pillTop = (height - pillHeight) / 2;
    final pillRect = Rect.fromLTWH(pillLeft, pillTop, pillWidth, pillHeight);
    final pillPaint = Paint()..color = const Color(0xFFF6FBF8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(pillRect, const Radius.circular(pillRadius)),
      pillPaint,
    );
    final textOffset = Offset(
      pillLeft + pillPadding,
      pillTop + (pillHeight - textPainter.height) / 2,
    );
    textPainter.paint(canvas, textOffset);

    final image =
        await recorder.endRecording().toImage(width.toInt(), height.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  String _fuelLabelFor(FuelOptionId? selection) {
    if (selection == null) return '';
    return _fuelOptions.firstWhere((option) => option.id == selection).label;
  }

  String _filterLabel() {
    final selection = _selectedFuel;
    final base =
        selection == null ? 'Selecciona combustible' : _fuelLabelFor(selection);
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

  Future<void> _applyRouteFilter(List<LatLng> routePoints) async {
    if (_stations.isEmpty) return;
    await _runWithFilterLoading(() async {
      final threshold = _routeThresholdMeters(routePoints);
      final sampled = _sampleRoute(routePoints, maxPoints: 350);
      final input = <String, dynamic>{
        'stationLat':
            _stations.map((station) => station.lat).toList(growable: false),
        'stationLng':
            _stations.map((station) => station.lng).toList(growable: false),
        'routeLat':
            sampled.map((point) => point.latitude).toList(growable: false),
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
      });
      await _rebuildMarkersForSelection();
    });
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
    controller.setMapStyle(_isMapDark ? _darkMapStyle : null);
  }

  bool get _isMapDark {
    return _isNightByLocation ??
        (WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark);
  }

  _MapUiPalette get _palette {
    if (_isMapDark) {
      return const _MapUiPalette(
        isDark: true,
        surface: Color(0xFF1C2320),
        surfaceAlt: Color(0xFF242E29),
        textPrimary: Colors.white,
        textSecondary: Colors.white70,
        border: Color(0xFF2F3A34),
        accent: _brandGreenLight,
        shadow: Colors.black87,
      );
    }
    return const _MapUiPalette(
      isDark: false,
      surface: Colors.white,
      surfaceAlt: Color(0xFFF3F7F4),
      textPrimary: Colors.black87,
      textSecondary: Colors.black54,
      border: Color(0xFFCBD8D1),
      accent: _brandGreenDark,
      shadow: Colors.black26,
    );
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
    final query = value.trim();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      if (query.length < 3) {
        _autocompleteRequestId++;
        setState(() {
          _predictions = [];
          _loadingPredictions = false;
        });
        return;
      }
      _fetchPredictions(query);
    });
  }

  Future<void> _onSearchSubmitted(String value) async {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 3) return;
    if (_predictions.isNotEmpty) {
      await _onPredictionSelected(_predictions.first);
      return;
    }
    setState(() => _loadingPredictions = true);
    try {
      final results = await _placesApi.autocomplete(
        input: query,
        sessionToken: _sessionToken,
      );
      if (!mounted) return;
      if (results.isEmpty) {
        setState(() {
          _predictions = [];
          _loadingPredictions = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay resultados.')),
        );
        return;
      }
      setState(() {
        _predictions = results;
        _loadingPredictions = false;
      });
      await _onPredictionSelected(results.first);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _predictions = [];
        _loadingPredictions = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo buscar el destino.')),
      );
    }
  }

  Future<void> _fetchPredictions(String input) async {
    final requestId = ++_autocompleteRequestId;
    setState(() => _loadingPredictions = true);
    try {
      final results = await _placesApi.autocomplete(
        input: input,
        sessionToken: _sessionToken,
      );
      if (!mounted || requestId != _autocompleteRequestId) return;
      setState(() {
        _predictions = results;
        _loadingPredictions = false;
      });
    } catch (_) {
      if (!mounted || requestId != _autocompleteRequestId) return;
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
      isScrollControlled: true,
      builder: (context) => StationSheet(
        station: station,
        markerColor: markerColor,
        onNavigate: () => _openDefaultNavigation(station),
      ),
    );
  }

  Future<void> _drawRouteToDestination(double destLat, double destLng) async {
    final current = _currentPosition ?? await _ensureCurrentPosition();
    if (current == null) return;

    try {
      final points = await _directionsApi.fetchRoute(
        originLat: current.latitude,
        originLng: current.longitude,
        destLat: destLat,
        destLng: destLng,
      );
      if (!mounted) return;

      final polylinePoints =
          points.map((point) => LatLng(point['lat']!, point['lng']!)).toList();
      setState(() {
        _routePolylines = {
          Polyline(
            polylineId: const PolylineId('route'),
            color: const Color(0xFF0B6E4F),
            width: 5,
            points: polylinePoints,
          ),
        };
        _hasRoute = polylinePoints.isNotEmpty;
        _routePoints = polylinePoints;
      });

      if (polylinePoints.isNotEmpty) {
        await _applyRouteFilter(polylinePoints);
        await _fitRouteBounds(polylinePoints);
      } else {
        setState(() {
          _routeStations = [];
          _hasRoute = false;
          _routePoints = [];
        });
        _rebuildMarkersForSelection();
        await _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(destLat, destLng), 11),
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
      minLat = minLat == null
          ? point.latitude
          : minLat < point.latitude
              ? minLat
              : point.latitude;
      maxLat = maxLat == null
          ? point.latitude
          : maxLat > point.latitude
              ? maxLat
              : point.latitude;
      minLng = minLng == null
          ? point.longitude
          : minLng < point.longitude
              ? minLng
              : point.longitude;
      maxLng = maxLng == null
          ? point.longitude
          : maxLng > point.longitude
              ? maxLng
              : point.longitude;
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

  Future<Position?> _ensureCurrentPosition() async {
    if (_currentPosition != null) return _currentPosition;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Activa los servicios de ubicación.')),
        );
      }
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permiso de ubicación denegado.')),
        );
      }
      return null;
    }

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    _currentPosition = position;
    _lastLat = position.latitude;
    _lastLng = position.longitude;
    await _refreshNightMode(position.latitude, position.longitude);
    return position;
  }

  Future<void> _onRoutePressed() async {
    if (_hasRoute && _routePoints.isNotEmpty) {
      await _fitRouteBounds(_routePoints);
      return;
    }
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

  Future<void> _clearRoute() async {
    setState(() {
      _routePolylines = {};
      _routeStations = [];
      _routePoints = [];
      _hasRoute = false;
    });
    await _rebuildMarkersForSelection();
  }

  Future<void> _clearRouteAndSearch() async {
    FocusScope.of(context).unfocus();
    _searchController.clear();
    _sessionToken = _uuid.v4();
    setState(() {
      _predictions = [];
      _destinationLat = null;
      _destinationLng = null;
    });
    await _clearRoute();
  }

  Future<void> _fitRouteBounds(List<LatLng> points) async {
    if (points.isEmpty) return;
    final bounds = _boundsFromLatLng(points);
    await _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 48),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.hasRoute,
    required this.palette,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final bool hasRoute;
  final _MapUiPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final showClear = value.text.isNotEmpty || hasRoute;
          return TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            style: TextStyle(color: palette.textPrimary),
            cursorColor: palette.accent,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search, color: palette.textSecondary),
              suffixIcon: showClear
                  ? IconButton(
                      icon: Icon(Icons.close, color: palette.textSecondary),
                      tooltip: 'Limpiar',
                      onPressed: onClear,
                    )
                  : null,
              hintText: 'Ir a',
              hintStyle: TextStyle(color: palette.textSecondary),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          );
        },
      ),
    );
  }
}

class _PredictionsList extends StatelessWidget {
  const _PredictionsList({
    required this.isLoading,
    required this.predictions,
    required this.onSelected,
    required this.palette,
    required this.maxHeight,
  });

  final bool isLoading;
  final List<PlacePrediction> predictions;
  final ValueChanged<PlacePrediction> onSelected;
  final _MapUiPalette palette;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withOpacity(0.3),
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
                  leading: Icon(Icons.place, color: palette.textSecondary),
                  title: Text(
                    prediction.primaryText,
                    style: TextStyle(color: palette.textPrimary),
                  ),
                  subtitle: prediction.secondaryText.isEmpty
                      ? null
                      : Text(
                          prediction.secondaryText,
                          style: TextStyle(color: palette.textSecondary),
                        ),
                  onTap: () => onSelected(prediction),
                );
              },
            ),
    );
  }
}

class _TutorialOverlay extends StatelessWidget {
  const _TutorialOverlay({
    required this.step,
    required this.stepIndex,
    required this.totalSteps,
    required this.targetRect,
    required this.onSkip,
    required this.onNext,
  });

  final _TutorialStep step;
  final int stepIndex;
  final int totalSteps;
  final Rect? targetRect;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final safe = media.padding;
    final screenHeight = media.size.height;
    final hasTarget = targetRect != null;
    final hole =
        (targetRect ?? Rect.fromLTWH(0, screenHeight * 0.5, 0, 0)).inflate(12);
    final preferBelow = !hasTarget || hole.center.dy < screenHeight * 0.6;
    final maxCardHeight = 210.0;
    final minTop = safe.top + 16;
    final maxTop = screenHeight - safe.bottom - maxCardHeight - 16;
    final minBottom = safe.bottom + 16;
    final maxBottom = screenHeight - safe.top - maxCardHeight - 16;
    double? top;
    double? bottom;
    if (preferBelow) {
      final proposed = (hasTarget ? hole.bottom : screenHeight * 0.28) + 16;
      top = math.min(maxTop, math.max(minTop, proposed));
    } else {
      final proposed =
          (screenHeight - (hasTarget ? hole.top : screenHeight * 0.5)) + 16;
      bottom = math.min(maxBottom, math.max(minBottom, proposed));
    }

    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: CustomPaint(
              painter: _TutorialPainter(
                holeRect: hole,
                overlayColor: Colors.black.withValues(alpha: 0.55),
              ),
            ),
          ),
          Positioned(
            top: safe.top + 4,
            right: 16,
            child: TextButton(
              onPressed: onSkip,
              child: const Text('Saltar'),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: top,
            bottom: bottom,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      step.description,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          '${stepIndex + 1} / $totalSteps',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: onNext,
                          child: Text(
                            stepIndex == totalSteps - 1
                                ? 'Empezar'
                                : 'Siguiente',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TutorialPainter extends CustomPainter {
  _TutorialPainter({
    required this.holeRect,
    required this.overlayColor,
  });

  final Rect? holeRect;
  final Color overlayColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.saveLayer(rect, Paint());
    canvas.drawRect(rect, Paint()..color = overlayColor);
    if (holeRect != null) {
      final clearPaint = Paint()..blendMode = BlendMode.clear;
      final rrect = RRect.fromRectAndRadius(
        holeRect!,
        const Radius.circular(16),
      );
      canvas.drawRRect(rrect, clearPaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TutorialPainter oldDelegate) {
    return oldDelegate.holeRect != holeRect ||
        oldDelegate.overlayColor != overlayColor;
  }
}

class _TutorialStep {
  const _TutorialStep({
    required this.title,
    required this.description,
    required this.targetKey,
  });

  final String title;
  final String description;
  final GlobalKey targetKey;
}

class _PriceIconKey {
  const _PriceIconKey(this.hue, this.label);

  final double hue;
  final String label;

  @override
  bool operator ==(Object other) {
    return other is _PriceIconKey &&
        other.hue == hue &&
        other.label == label;
  }

  @override
  int get hashCode => Object.hash(hue, label);
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
    super.key,
    required this.label,
    required this.onPressed,
    required this.palette,
  });

  final String label;
  final VoidCallback onPressed;
  final _MapUiPalette palette;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.local_gas_station),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        backgroundColor: palette.surface,
        foregroundColor: palette.textPrimary,
        side: BorderSide(color: palette.border),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class _MapUiPalette {
  const _MapUiPalette({
    required this.isDark,
    required this.surface,
    required this.surfaceAlt,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.accent,
    required this.shadow,
  });

  final bool isDark;
  final Color surface;
  final Color surfaceAlt;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color accent;
  final Color shadow;
}

Map<String, dynamic> _filterStationsForSelection(
  Map<String, dynamic> input,
) {
  final entries = (input['entries'] as List)
      .cast<Map>()
      .map((entry) => (
            index: entry['index'] as int,
            price: (entry['price'] as num).toDouble(),
          ))
      .toList();
  if (entries.isEmpty) {
    return {
      'indices': <int>[],
      'minPrice': 0.0,
      'maxPrice': 0.0,
    };
  }

  var filtered = entries;
  final filterCheapestOnly = input['filterCheapestOnly'] as bool? ?? false;
  if (filterCheapestOnly) {
    final prices = entries.map((entry) => entry.price).toList()..sort();
    final cutoffIndex = ((prices.length - 1) * 0.25).round();
    final cutoff = prices[cutoffIndex];
    filtered = entries.where((entry) => entry.price <= cutoff).toList();
  }

  if (filtered.isEmpty) {
    return {
      'indices': <int>[],
      'minPrice': 0.0,
      'maxPrice': 0.0,
    };
  }

  var minPrice = filtered.first.price;
  var maxPrice = filtered.first.price;
  for (final entry in filtered.skip(1)) {
    if (entry.price < minPrice) minPrice = entry.price;
    if (entry.price > maxPrice) maxPrice = entry.price;
  }

  return {
    'indices': filtered.map((entry) => entry.index).toList(),
    'minPrice': minPrice,
    'maxPrice': maxPrice,
  };
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
