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

import '../models/filter_result.dart';
import '../models/fuel_option.dart';
import '../models/place_prediction.dart';
import '../models/station.dart';
import '../services/directions_api.dart';
import '../services/fuel_api.dart';
import '../services/navigation_launcher.dart';
import '../services/places_api.dart';
import '../services/sun_times_api.dart';
import '../utils/price_color.dart';
import '../utils/station_filter.dart';
import '../widgets/error_state.dart';
import '../widgets/filter_button.dart';
import '../widgets/map_search_bar.dart';
import '../widgets/predictions_list.dart';
import '../widgets/price_legend.dart';
import '../widgets/station_sheet.dart';
import '../widgets/tutorial_overlay.dart';
import '../theme/app_theme.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  // UI configuration.
  static const double _unselectedHue = BitmapDescriptor.hueAzure;
  static const Color _brandGreenLight = Color(0xFF57D39D);
  static const int _iosViewportThreshold = 1500;
  static const int _viewportFilterThreshold = 700;
  static const int _downsampleThreshold = 500;

  static const List<FuelOption> _fuelOptions = [
    FuelOption(
      id: FuelOptionId.gasolina95,
      label: 'Gasolina 95',
      color: Color(0xFF1B8E3E),
    ),
    FuelOption(
      id: FuelOptionId.gasoleoA,
      label: 'Diesel normal',
      color: Color(0xFF30343A),
    ),
    FuelOption(
      id: FuelOptionId.glp,
      label: 'GLP',
      color: Color(0xFFF28C28),
    ),
    FuelOption(
      id: FuelOptionId.gasolina98,
      label: 'Gasolina 98',
      color: Color(0xFF4AAE6C),
    ),
    FuelOption(
      id: FuelOptionId.gnc,
      label: 'GNC',
      color: Color(0xFF2B6CB0),
    ),
    FuelOption(
      id: FuelOptionId.gasoleoPremium,
      label: 'Diesel premium',
      color: Color(0xFFC79B2A),
    ),
  ];

  // Controllers and services.
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

  // Map state.
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
  bool _includeRestricted = false;
  bool _showPriceLabels = true;
  int? _routeRadiusMeters;
  String? _stationsError;
  String? _stationsErrorDetails;
  List<Station> _stations = [];
  final Map<String, Map<FuelOptionId, double>> _stationFuelPrices = {};
  double? _minPrice;
  double? _maxPrice;
  Set<Marker> _stationMarkers = const {};
  FuelOptionId? _selectedFuel;
  final Map<int, BitmapDescriptor> _simpleIconCache = {};
  final Map<int, Future<BitmapDescriptor>> _simpleIconLoaders = {};
  final Map<String, BitmapDescriptor> _priceIconCache = {};
  final Map<String, Future<BitmapDescriptor>> _priceIconLoaders = {};
  static const Color _restrictedMarkerColor = Color(0xFF5D6A70);
  static const String _prefsFuelKey = 'filter_fuel_id';
  static const String _prefsCheapestKey = 'filter_cheapest_only';
  static const String _prefsIncludeRestrictedKey = 'filter_include_restricted';
  static const String _prefsShowPricesKey = 'filter_show_prices';
  static const String _prefsRouteRadiusKey = 'route_radius_meters';
  static const int _routeRadiusAutoSentinel = -1;
  bool _showTutorial = false;
  int _tutorialStepIndex = 0;
  late final List<TutorialStep> _tutorialSteps = [
    TutorialStep(
      title: 'Busca tu destino',
      description:
          'Escribe un lugar y elige una sugerencia para trazar la ruta.',
      targetKey: _searchKey,
    ),
    TutorialStep(
      title: 'Ver la ruta',
      description:
          'La ruta se mostrara en el mapa con las gasolineras que esten de camino.',
      targetKey: _routeKey,
    ),
    TutorialStep(
      title: 'Filtra combustible',
      description:
          'Selecciona el tipo de combustible y activa “Solo mas baratas” si '
          'quieres ver las estaciones con el mejor precio.',
      targetKey: _filterKey,
    ),
    TutorialStep(
      title: 'Mostrar precios',
      description:
          'Desde el filtro puedes decidir si quieres ver el precio junto al '
          'icono de cada gasolinera.',
      targetKey: _filterKey,
    ),
    TutorialStep(
      title: 'Selecciona el tipo de venta',
      description:
          'Puedes mostrar gasolineras con venta restringida (flotas o '
          'clientes autorizados) desde el filtro.',
      targetKey: _filterKey,
    ),
    TutorialStep(
      title: 'Radio de ruta',
      description:
          'Si tienes ruta activa puedes ajustar el radio manualmente o '
          'dejarlo en automatico desde el filtro.',
      targetKey: _filterKey,
    ),
    TutorialStep(
      title: 'Precios a simple vista',
      description:
          'Cuando el precio esta activado, veras el importe junto al icono '
          'de la gasolinera.',
      targetKey: _mapKey,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionToken = _uuid.v4();
    _loadMapStyle();
    _loadStations();
    _restoreFilterPreferences();
    _loadTutorialPreference();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    _nightTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshNightModeFromCache();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _isMapDark;
    final theme =
        AppTheme.build(isDark ? Brightness.dark : Brightness.light);
    final colorScheme = theme.colorScheme;
    final baseOverlayStyle = theme.brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    final overlayStyle = baseOverlayStyle.copyWith(
      statusBarColor: Colors.transparent,
    );
    return Theme(
      data: theme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
        child: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: _buildMapBody(),
              ),
              SafeArea(
                child: Stack(
                  children: [
                    Positioned(
                      left: 16,
                      right: 16,
                      top: 12,
                      child: Column(
                        key: _searchKey,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MapSearchBar(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            onChanged: _onSearchChanged,
                            onSubmitted: _onSearchSubmitted,
                            onClear: _clearRouteAndSearch,
                            hasRoute: _hasRoute,
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxWidth: 260),
                              child: FilterButton(
                                key: _filterKey,
                                label: _filterLabel(),
                                onPressed: _openFuelFilter,
                                icon: Icons.local_gas_station,
                              ),
                            ),
                          ),
                          if (_predictions.isNotEmpty || _loadingPredictions)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: PredictionsList(
                                isLoading: _loadingPredictions,
                                predictions: _predictions,
                                onSelected: _onPredictionSelected,
                                maxHeight: _predictionsMaxHeight(context),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_selectedFuel != null && _minPrice != null)
                            PriceLegend(
                              minPrice: _minPrice!,
                              maxPrice: _maxPrice!,
                              backgroundColor: colorScheme.surface,
                              textColor: colorScheme.onSurface,
                              secondaryTextColor:
                                  colorScheme.onSurfaceVariant,
                              shadowColor: theme.shadowColor,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_showTutorial)
                TutorialOverlay(
                  step: _tutorialSteps[_tutorialStepIndex],
                  stepIndex: _tutorialStepIndex,
                  totalSteps: _tutorialSteps.length,
                  targetRect: _currentTutorialTargetRect,
                  onSkip: _dismissTutorial,
                  onNext: _advanceTutorial,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapBody() {
    if (_stationsError != null) {
      return ErrorState(
        message: _stationsError!,
        details: _stationsErrorDetails,
        onRetry: _loadStations,
      );
    }

    if (_loadingStations) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        Positioned.fill(
          child: GoogleMap(
            key: _mapKey,
            initialCameraPosition: const CameraPosition(
              target: LatLng(40.4168, -3.7038),
              zoom: 5.6,
            ),
            style: _isMapDark ? _darkMapStyle : null,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (controller) async {
              _mapController = controller;
              await _moveToCurrentPosition();
              if (_showTutorial) {
                setState(() {});
              }
            },
            onCameraIdle: _onCameraIdle,
            markers: _stationMarkers,
            polylines: _routePolylines,
            onTap: (_) => _dismissKeyboard(),
          ),
        ),
        if (_isApplyingFilter)
          Positioned.fill(
            child: Container(
              color: Colors.black12,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ),
        Positioned(
          right: 16,
          bottom: 108,
          child: FloatingActionButton(
            heroTag: 'locate',
            onPressed: _moveToCurrentPosition,
            elevation: 4,
            child: const Icon(Icons.my_location),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 48,
          child: FloatingActionButton(
            key: _routeKey,
            heroTag: 'route',
            onPressed: _onRoutePressed,
            elevation: 4,
            child: const Icon(Icons.alt_route),
          ),
        ),
      ],
    );
  }

  double _predictionsMaxHeight(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.42;
    return math.min(maxHeight, 320);
  }

  Rect? get _currentTutorialTargetRect {
    final key = _tutorialSteps[_tutorialStepIndex].targetKey;
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      final offset = renderObject.localToGlobal(Offset.zero);
      return offset & renderObject.size;
    }
    return null;
  }

  void _dismissKeyboard() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null) {
      focus.unfocus();
    }
  }

  void _dismissTutorial() {
    setState(() {
      _showTutorial = false;
    });
    _saveTutorialPreference(false);
  }

  void _advanceTutorial() {
    if (_tutorialStepIndex >= _tutorialSteps.length - 1) {
      _dismissTutorial();
      return;
    }
    setState(() {
      _tutorialStepIndex += 1;
    });
  }

  Future<void> _loadTutorialPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('show_tutorial') ?? true;
    if (!mounted) return;
    setState(() {
      _showTutorial = enabled;
      _tutorialStepIndex = 0;
    });
  }

  Future<void> _saveTutorialPreference(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_tutorial', value);
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
      final prices = _buildFuelPriceIndex(stations);
      setState(() {
        _stations = stations;
        _stationFuelPrices
          ..clear()
          ..addAll(prices);
        _loadingStations = false;
      });
      await _rebuildMarkersForSelection();
    } catch (error, stack) {
      debugPrint('Error loading stations: $error');
      debugPrint(stack.toString());
      if (!mounted) return;
      setState(() {
        _stationsError =
            'No se pudo cargar el listado de estaciones. Intentalo de nuevo.';
        _stationsErrorDetails = error.toString();
        _loadingStations = false;
      });
    }
  }

  Future<void> _openFuelFilter() async {
    final sheetTheme =
        AppTheme.build(_isMapDark ? Brightness.dark : Brightness.light);
    final result = await showModalBottomSheet<FilterResult>(
      context: context,
      backgroundColor: sheetTheme.colorScheme.surface,
      shape: sheetTheme.bottomSheetTheme.shape,
      clipBehavior: Clip.antiAlias,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return Theme(
          data: sheetTheme,
          child: Builder(
            builder: (context) {
              final theme = Theme.of(context);
              FuelOptionId? tempSelection = _selectedFuel;
              bool tempCheapestOnly = _filterCheapestOnly;
              bool tempIncludeRestricted = _includeRestricted;
              bool tempShowPrices = _showPriceLabels;
              bool tempRouteAuto = _routeRadiusMeters == null;
              double tempRouteMeters = (_routeRadiusMeters ?? 2000).toDouble();
              int? tempRouteRadiusMeters = _routeRadiusMeters;
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Selecciona combustible',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            TextButton(
                              onPressed: (tempSelection == null &&
                                      !tempCheapestOnly &&
                                      !tempIncludeRestricted &&
                                      tempShowPrices &&
                                      tempRouteAuto)
                                  ? null
                                  : () => setModalState(() {
                                        tempSelection = null;
                                        tempCheapestOnly = false;
                                        tempIncludeRestricted = false;
                                        tempShowPrices = true;
                                        tempRouteAuto = true;
                                        tempRouteMeters = 2000;
                                        tempRouteRadiusMeters = null;
                                      }),
                              child: const Text('Limpiar'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ..._fuelOptions.map((option) {
                              final chipLabel = Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: option.color,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    option.label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              );
                              return ChoiceChip(
                                label: chipLabel,
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
                          subtitle:
                              const Text('Muestra solo el tramo mas economico.'),
                          value: tempCheapestOnly,
                          onChanged: (value) => setModalState(() {
                            tempCheapestOnly = value;
                          }),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Incluir venta restringida'),
                          subtitle: const Text(
                              'Solo para flotas o clientes autorizados.'),
                          value: tempIncludeRestricted,
                          onChanged: (value) => setModalState(() {
                            tempIncludeRestricted = value;
                          }),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Mostrar precios en el mapa'),
                          subtitle: const Text(
                              'Muestra el precio junto al icono del surtidor.'),
                          value: tempShowPrices,
                          onChanged: (value) => setModalState(() {
                            tempShowPrices = value;
                          }),
                        ),
                        if (_hasRoute)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 8),
                              Text(
                                'Radio en ruta',
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Automatico'),
                                subtitle: const Text(
                                  'Ajusta el radio segun la longitud de la ruta.',
                                ),
                                value: tempRouteAuto,
                                onChanged: (value) => setModalState(() {
                                  tempRouteAuto = value;
                                  if (tempRouteAuto) {
                                    tempRouteRadiusMeters = null;
                                  } else {
                                    tempRouteMeters =
                                        tempRouteMeters.clamp(500, 10000);
                                    tempRouteRadiusMeters =
                                        tempRouteMeters.round();
                                  }
                                }),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Radio: ${_formatRouteRadius(tempRouteMeters.round())}',
                                style: theme.textTheme.bodyMedium,
                              ),
                              Slider(
                                value: tempRouteMeters.clamp(500, 10000),
                                min: 500,
                                max: 10000,
                                divisions: 95,
                                label: _formatRouteRadius(
                                  tempRouteMeters.round(),
                                ),
                                onChanged: tempRouteAuto
                                    ? null
                                    : (value) => setModalState(() {
                                          tempRouteMeters =
                                              (value / 100).round() * 100.0;
                                          tempRouteRadiusMeters =
                                              tempRouteMeters.round();
                                        }),
                              ),
                            ],
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
                                  FilterResult(
                                    fuel: tempSelection,
                                    cheapestOnly: tempCheapestOnly,
                                    includeRestricted: tempIncludeRestricted,
                                    showPrices: tempShowPrices,
                                    routeRadiusMeters: tempRouteRadiusMeters,
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
          ),
        );
      },
    );

    if (result == null) return;
    await _applyFilter(
      result.fuel,
      result.cheapestOnly,
      result.includeRestricted,
      result.showPrices,
      result.routeRadiusMeters,
    );
  }

  Future<void> _applyFilter(
    FuelOptionId? selection,
    bool cheapestOnly,
    bool includeRestricted,
    bool showPrices,
    int? routeRadiusMeters,
  ) async {
    final previousRouteRadius = _routeRadiusMeters;
    setState(() {
      _selectedFuel = selection;
      _filterCheapestOnly = cheapestOnly;
      _includeRestricted = includeRestricted;
      _showPriceLabels = showPrices;
      _routeRadiusMeters = routeRadiusMeters;
    });
    await _persistFilterPreferences();
    final routeRadiusChanged = previousRouteRadius != _routeRadiusMeters;
    if (_hasRoute && _routePoints.isNotEmpty && routeRadiusChanged) {
      await _applyRouteFilter(_routePoints);
      return;
    }
    await _runWithFilterLoading(_rebuildMarkersForSelection);
  }

  Future<void> _persistFilterPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (_selectedFuel == null) {
      await prefs.remove(_prefsFuelKey);
    } else {
      await prefs.setString(_prefsFuelKey, _selectedFuel!.name);
    }
    await prefs.setBool(_prefsCheapestKey, _filterCheapestOnly);
    await prefs.setBool(_prefsIncludeRestrictedKey, _includeRestricted);
    await prefs.setBool(_prefsShowPricesKey, _showPriceLabels);
    await prefs.setInt(
      _prefsRouteRadiusKey,
      _routeRadiusMeters ?? _routeRadiusAutoSentinel,
    );
  }

  Future<void> _restoreFilterPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final storedFuel = prefs.getString(_prefsFuelKey);
    final storedCheapest = prefs.getBool(_prefsCheapestKey) ?? false;
    final storedRestricted = prefs.getBool(_prefsIncludeRestrictedKey) ?? false;
    final storedShowPrices = prefs.getBool(_prefsShowPricesKey) ?? true;
    final storedRadius = prefs.getInt(_prefsRouteRadiusKey);
    FuelOptionId? restoredFuel;
    if (storedFuel != null) {
      for (final option in FuelOptionId.values) {
        if (option.name == storedFuel) {
          restoredFuel = option;
          break;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _selectedFuel = restoredFuel;
      _filterCheapestOnly = storedCheapest;
      _includeRestricted = storedRestricted;
      _showPriceLabels = storedShowPrices;
      if (storedRadius != null) {
        _routeRadiusMeters =
            storedRadius == _routeRadiusAutoSentinel ? null : storedRadius;
      }
    });
    if (!_loadingStations && _stations.isNotEmpty) {
      await _runWithFilterLoading(_rebuildMarkersForSelection);
    }
  }

  Future<void> _runWithFilterLoading(Future<void> Function() task) async {
    setState(() {
      _isApplyingFilter = true;
    });
    try {
      await task();
    } finally {
      if (mounted) {
        setState(() {
          _isApplyingFilter = false;
        });
      }
    }
  }

  Future<void> _rebuildMarkersForSelection() async {
    if (_stations.isEmpty) return;
    final baseStations = _hasRoute ? _routeStations : _stations;
    final visibleStations = _includeRestricted
        ? baseStations
        : baseStations.where((station) => !station.isRestricted).toList();
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

    if (visibleStations.isEmpty) {
      setState(() {
        _stationMarkers = const {};
        _minPrice = null;
        _maxPrice = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay estaciones publicas con el filtro actual.'),
        ),
      );
      return;
    }

    if (_selectedFuel == null) {
      setState(() {
        _minPrice = null;
        _maxPrice = null;
      });
      await _setMarkersForStations(visibleStations);
      return;
    }

    final entries = <Map<String, dynamic>>[];
    for (var i = 0; i < visibleStations.length; i++) {
      final station = visibleStations[i];
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

    final result = await compute(filterStationsForSelection, {
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
    final stationsToUse = indices.map((i) => visibleStations[i]).toList();
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

    if (zoom < 8 && stationsToRender.length > _downsampleThreshold) {
      stationsToRender = _downsample(stationsToRender);
    }

    final markers = await _buildMarkers(stationsToRender);
    if (!mounted) return;
    await _setMarkersInBatches(markers);
  }

  List<Station> _stationsInBounds(
    List<Station> stations,
    LatLngBounds bounds,
  ) {
    return stations.where((station) {
      final lat = station.lat;
      final lng = station.lng;
      return lat >= bounds.southwest.latitude &&
          lat <= bounds.northeast.latitude &&
          lng >= bounds.southwest.longitude &&
          lng <= bounds.northeast.longitude;
    }).toList();
  }

  List<Station> _downsample(List<Station> stations) {
    if (stations.length <= _downsampleThreshold) return stations;
    final step = (stations.length / _downsampleThreshold).ceil();
    final sampled = <Station>[];
    for (var i = 0; i < stations.length; i += step) {
      sampled.add(stations[i]);
    }
    return sampled;
  }

  LatLngBounds _expandBounds(LatLngBounds bounds, double factor) {
    final latDelta = bounds.northeast.latitude - bounds.southwest.latitude;
    final lngDelta = bounds.northeast.longitude - bounds.southwest.longitude;
    return LatLngBounds(
      southwest: LatLng(
        bounds.southwest.latitude - latDelta * factor,
        bounds.southwest.longitude - lngDelta * factor,
      ),
      northeast: LatLng(
        bounds.northeast.latitude + latDelta * factor,
        bounds.northeast.longitude + lngDelta * factor,
      ),
    );
  }

  Future<Set<Marker>> _buildMarkers(List<Station> stations) async {
    if (stations.isEmpty) return const {};
    final minPrice = _markerMinPrice;
    final maxPrice = _markerMaxPrice;
    if (_showPriceLabels &&
        _selectedFuel != null &&
        minPrice != null &&
        maxPrice != null) {
      return _buildPriceMarkers(stations, minPrice, maxPrice);
    }

    final iconKeys = <int>{};
    final stationIcons = <String, int>{};
    for (final station in stations) {
      final color = _markerColorForStation(station);
      final colorValue = color.toARGB32();
      iconKeys.add(colorValue);
      stationIcons[station.id] = colorValue;
    }
    await Future.wait(
      iconKeys.map((value) => _iconForColor(Color(value))),
    );

    return stations.map((station) {
      final colorValue = stationIcons[station.id];
      if (colorValue == null) return null;
      final icon = _simpleIconCache[colorValue];
      if (icon == null) return null;
      return Marker(
        markerId: MarkerId(station.id),
        position: LatLng(station.lat, station.lng),
        icon: icon,
        onTap: () => _showStationSheet(station),
      );
    }).whereType<Marker>().toSet();
  }

  Future<BitmapDescriptor> _iconForColor(Color color) async {
    final key = color.toARGB32();
    final cached = _simpleIconCache[key];
    if (cached != null) return cached;
    final loader = _simpleIconLoaders[key] ??= _drawIcon(color);
    final icon = await loader;
    _simpleIconCache[key] = icon;
    return icon;
  }

  Future<Set<Marker>> _buildPriceMarkers(
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
      final color =
          station.isRestricted ? _restrictedMarkerColor : _colorForHue(hue);
      final label = _formatPrice(price);
      final key = _PriceIconKey(color.toARGB32(), label);
      iconKeys.add(key);
      stationIcons[station.id] = key;
    }
    await Future.wait(
      iconKeys.map(
        (key) => _iconForColorWithPrice(Color(key.colorValue), key.label),
      ),
    );
    return stations.map((station) {
      final key = stationIcons[station.id];
      if (key == null) return null;
      final icon = _priceIconCache[_priceCacheKey(key.colorValue, key.label)];
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

  Future<void> _showStationSheet(Station station) async {
    final markerColor = _markerColorForStation(station);
    final sheetTheme =
        AppTheme.build(_isMapDark ? Brightness.dark : Brightness.light);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: sheetTheme.colorScheme.surface,
      shape: sheetTheme.bottomSheetTheme.shape,
      clipBehavior: Clip.antiAlias,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return Theme(
          data: sheetTheme,
          child: StationSheet(
            station: station,
            markerColor: markerColor,
            onNavigate: () => _launchNavigation(station),
          ),
        );
      },
    );
  }

  Future<void> _launchNavigation(Station station) async {
    if (await _ensureCurrentPosition() == null) return;
    await _launcher.openDefaultMaps(station.lat, station.lng);
  }

  String _formatPrice(double price) {
    return price.toStringAsFixed(3);
  }

  double _bucketHue(double hue) {
    return (hue / 4).round() * 4.0;
  }

  Color _colorForHue(double hue) {
    return HSVColor.fromAHSV(1, hue, 0.85, 0.9).toColor();
  }

  String _priceCacheKey(int colorValue, String label) {
    return '$colorValue-$label';
  }

  double _markerScale() {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ratio = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
      if (ratio > 0) {
        return 1 / ratio;
      }
    }
    return 1;
  }

  Future<BitmapDescriptor> _iconForColorWithPrice(
    Color color,
    String label,
  ) async {
    final key = _priceCacheKey(color.toARGB32(), label);
    final cached = _priceIconCache[key];
    if (cached != null) return cached;

    final loader = _priceIconLoaders[key] ??= _drawIconWithPrice(color, label);
    final icon = await loader;
    _priceIconCache[key] = icon;
    return icon;
  }

  Future<BitmapDescriptor> _drawIconWithPrice(Color color, String label) async {
    const double baseCircleSize = 78;
    const double basePillHeight = 58;
    const double basePillPadding = 20;
    const double basePillRadius = 26;
    final scale = _markerScale();
    final circleSize = baseCircleSize * scale;
    final pillHeight = basePillHeight * scale;
    final pillPadding = basePillPadding * scale;
    final pillRadius = basePillRadius * scale;
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 32 * scale,
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
        children: [
          TextSpan(
            text: ' €',
            style: TextStyle(
              fontSize: 33 * scale,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final pillWidth = textPainter.width + pillPadding * 2;
    final width = circleSize + pillWidth + (6 * scale);
    final height = math.max(circleSize, pillHeight);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width, height),
    );

    final center = Offset(circleSize / 2, height / 2);
    final radius = circleSize / 2;
    final paint = Paint()..color = color;
    canvas.drawCircle(center, radius, paint);

    const icon = Icons.local_gas_station;
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 58 * scale,
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

    final pillLeft = circleSize - (6 * scale);
    final pillTop = (height - pillHeight) / 2;
    final pillRect = Rect.fromLTWH(pillLeft, pillTop, pillWidth, pillHeight);
    final pillPaint = Paint()..color = const Color(0xFFF6FBF8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(pillRect, Radius.circular(pillRadius)),
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
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      bitmapScaling: MapBitmapScaling.none,
    );
  }

  Future<BitmapDescriptor> _drawIcon(Color color) async {
    const double baseSize = 70;
    final scale = _markerScale();
    final size = baseSize * scale;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, size, size),
    );

    final center = Offset(size / 2, size / 2);
    final paint = Paint()..color = color;
    canvas.drawCircle(center, size / 2, paint);

    const icon = Icons.local_gas_station;
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 46 * scale,
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

    final image =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      bitmapScaling: MapBitmapScaling.none,
    );
  }

  String _fuelLabelFor(FuelOptionId? selection) {
    if (selection == null) return '';
    return _fuelOptions.firstWhere((option) => option.id == selection).label;
  }

  String _filterLabel() {
    final selection = _selectedFuel;
    var base = selection == null ? 'Selecciona combustible' : _fuelLabelFor(selection);
    if (_filterCheapestOnly) {
      base = '$base · mas baratas';
    }
    if (_includeRestricted) {
      base = '$base · restringidas';
    }
    if (!_showPriceLabels) {
      base = '$base · sin precios';
    }
    if (_hasRoute) {
      final radius = _routeRadiusMeters;
      final radiusLabel =
          radius == null ? 'radio auto' : 'radio ${_formatRouteRadius(radius)}';
      base = '$base · $radiusLabel';
    }
    return base;
  }

  Color _markerColorForStation(Station station) {
    if (station.isRestricted) {
      return _restrictedMarkerColor;
    }
    if (_selectedFuel != null && _minPrice != null && _maxPrice != null) {
      final price = _priceForSelectedFuel(station);
      if (price != null) {
        return PriceColor.colorFor(price, _minPrice!, _maxPrice!);
      }
    }
    return const HSVColor.fromAHSV(1, _unselectedHue, 0.85, 0.9).toColor();
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
    final fixedRadius = _routeRadiusMeters;
    if (fixedRadius != null) return fixedRadius.toDouble();
    if (points.length < 2) return 2000;
    final length = _estimateRouteLengthMeters(points);
    if (length > 100000) return 2000;
    if (length > 50000) return 1800;
    return 1500;
  }

  String _formatRouteRadius(int meters) {
    if (meters < 1000) {
      return '$meters m';
    }
    if (meters % 1000 == 0) {
      return '${meters ~/ 1000} km';
    }
    final km = meters / 1000;
    return '${km.toStringAsFixed(1)} km';
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

  static double _distanceMeters(
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
        case 193: // A
        case 192: // A
        case 194: // A
        case 196: // A
          buffer.write('A');
          break;
        case 201: // E
        case 200: // E
        case 202: // E
        case 203: // E
          buffer.write('E');
          break;
        case 205: // I
        case 204: // I
        case 206: // I
        case 207: // I
          buffer.write('I');
          break;
        case 211: // O
        case 210: // O
        case 212: // O
        case 214: // O
          buffer.write('O');
          break;
        case 218: // U
        case 217: // U
        case 219: // U
        case 220: // U
          buffer.write('U');
          break;
        case 209: // N
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
        key.contains('GASESLICUADOSDELPETROLEO') ||
        key.contains('AUTOGAS') ||
        key.contains('GASLICUADO')) {
      return FuelOptionId.glp;
    }
    if (key.contains('GNC') ||
        key.contains('GNL') ||
        key.contains('GASNATURAL') ||
        key.contains('BIOGASNATURAL')) {
      return FuelOptionId.gnc;
    }
    return null;
  }

  Future<void> _loadMapStyle() async {
    try {
      _darkMapStyle = await rootBundle.loadString(
        'assets/map_style_dark.json',
      );
      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      // Silently ignore style loading failures.
    }
  }

  bool get _isMapDark {
    return _isNightByLocation ?? false;
  }

  Future<void> _refreshNightMode(double lat, double lng) async {
    try {
      final times = await _sunTimesApi.fetchSunTimes(lat, lng);
      final isNight = _sunTimesApi.isNight(times);
      if (!mounted) return;
      setState(() {
        _isNightByLocation = isNight;
      });
      _scheduleNightRefresh(times);
    } catch (_) {
      // Ignore sun time errors.
    }
  }

  void _scheduleNightRefresh(SunTimes times) {
    _nightTimer?.cancel();
    final now = DateTime.now();
    final nextChange = _sunTimesApi.nextTransition(times, now);
    if (nextChange == null) return;
    final delay = nextChange.difference(now);
    _nightTimer = Timer(delay, () {
      final lat = _lastLat;
      final lng = _lastLng;
      if (lat == null || lng == null) return;
      _refreshNightMode(lat, lng);
    });
  }

  void _refreshNightModeFromCache() {
    final lat = _lastLat;
    final lng = _lastLng;
    if (lat == null || lng == null) return;
    _refreshNightMode(lat, lng);
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _predictions = [];
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 350), () {
      _fetchPredictions(query);
    });
  }

  void _onSearchSubmitted(String query) async {
    _dismissKeyboard();
    if (_predictions.isNotEmpty) {
      await _onPredictionSelected(_predictions.first);
      return;
    }

    final results = await _placesApi.autocomplete(
      input: query,
      sessionToken: _sessionToken,
    );
    if (!mounted) return;
    if (results.isEmpty) {
      setState(() {
        _predictions = [];
      });
      return;
    }
    await _onPredictionSelected(results.first);
  }

  Future<void> _fetchPredictions(String query) async {
    _autocompleteRequestId++;
    final requestId = _autocompleteRequestId;
    setState(() {
      _loadingPredictions = true;
    });
    try {
      final results = await _placesApi.autocomplete(
        input: query,
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
    _dismissKeyboard();
    setState(() {
      _loadingPredictions = true;
      _predictions = [];
    });

    try {
      final location = await _placesApi.fetchPlaceLocation(
        placeId: prediction.placeId,
        sessionToken: _sessionToken,
      );
      if (!mounted) return;
      _sessionToken = _uuid.v4();
      _destinationLat = location['lat'];
      _destinationLng = location['lng'];
      _searchController.text = prediction.description;
      await _drawRouteToDestination(_destinationLat!, _destinationLng!);
      setState(() {
        _loadingPredictions = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingPredictions = false;
        _predictions = [];
      });
    }
  }

  Future<void> _drawRouteToDestination(double lat, double lng) async {
    final position = await _ensureCurrentPosition();
    if (position == null) return;

    try {
      final rawPoints = await _directionsApi.fetchRoute(
        originLat: position.latitude,
        originLng: position.longitude,
        destLat: lat,
        destLng: lng,
      );
      if (rawPoints.isEmpty) {
        throw Exception('Ruta sin puntos.');
      }
      final points = rawPoints
          .map((point) => LatLng(point['lat']!, point['lng']!))
          .toList();
      if (!mounted) return;
      setState(() {
        _routePolylines = {
          Polyline(
            polylineId: const PolylineId('route'),
            color: _brandGreenLight,
            width: 5,
            points: points,
          ),
        };
        _routePoints = points;
        _hasRoute = true;
      });
      await _fitRouteBounds(points);
      await _applyRouteFilter(points);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo trazar la ruta.')),
      );
    }
  }

  LatLngBounds _boundsFromLatLng(List<LatLng> points) {
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final point in points.skip(1)) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  static List<int> _stationsNearRoute(Map<String, dynamic> input) {
    final stationLat = (input['stationLat'] as List).cast<double>();
    final stationLng = (input['stationLng'] as List).cast<double>();
    final routeLat = (input['routeLat'] as List).cast<double>();
    final routeLng = (input['routeLng'] as List).cast<double>();
    final threshold = input['thresholdMeters'] as double;

    final indices = <int>[];
    for (var i = 0; i < stationLat.length; i++) {
      final stationPoint = LatLng(stationLat[i], stationLng[i]);
      if (_isStationNearRoute(stationPoint, routeLat, routeLng, threshold)) {
        indices.add(i);
      }
    }
    return indices;
  }

  static bool _isStationNearRoute(
    LatLng station,
    List<double> routeLat,
    List<double> routeLng,
    double threshold,
  ) {
    for (var i = 0; i < routeLat.length; i++) {
      final dist = _distanceMeters(
        station.latitude,
        station.longitude,
        routeLat[i],
        routeLng[i],
      );
      if (dist <= threshold) return true;
    }
    return false;
  }

  Future<void> _moveToCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Activa los servicios de ubicación.')),
        );
      }
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
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
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
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
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
    _dismissKeyboard();
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

class _PriceIconKey {
  const _PriceIconKey(this.colorValue, this.label);

  final int colorValue;
  final String label;

  @override
  bool operator ==(Object other) {
    return other is _PriceIconKey &&
        other.colorValue == colorValue &&
        other.label == label;
  }

  @override
  int get hashCode => Object.hash(colorValue, label);
}
