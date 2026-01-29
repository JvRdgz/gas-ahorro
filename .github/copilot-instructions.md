# Gas Ahorro - AI Coding Agent Instructions

## Project Overview
**Gas Ahorro** is a Flutter app that displays real-time gas station prices in Spain using Google Maps. The architecture follows a monolithic pattern with a single main state container (`MapScreen`) managing most UI and logic.

## Architecture & Data Flow

### Core Structure
- **lib/main.dart** - Single large widget (`_MapScreenState`) managing:
  - Google Maps display with station markers
  - Station data fetching and filtering
  - Route/navigation logic
  - Geolocation and sun time calculations
  - Tutorial/onboarding system
  
- **lib/models/** - Data classes:
  - `Station` - Gas station data (id, name, prices by fuel type, lat/lng, restriction status)
  - `PlacePrediction` - Google Places autocomplete results

- **lib/services/** - External API integration:
  - `FuelApi` - Fetches stations from Spain's Ministry of Industry API (JSON parsing with locale-aware parsing for decimals using commas)
  - `PlacesApi` - Google Places autocomplete and place details
  - `DirectionsApi` - Route directions polylines
  - `NavigationLauncher` - Opens native maps apps (Google Maps, Apple Maps, etc.)
  - `SunTimesApi` - Calculates sunrise/sunset for location-based dark mode

- **lib/utils/** - Helper utilities:
  - `price_color.dart` - HSL-based color mapping for price ranges (blue=cheap → red=expensive)

- **lib/widgets/** - Reusable components:
  - `StationSheet` - Bottom sheet showing station details and navigation button
  - `PriceLegend` - Visual legend for price-to-color mapping

### Key State Management Pattern
The `_MapScreenState` class holds 40+ state variables. Critical ones:
- `_stations` - All fetched gas stations
- `_stationFuelPrices` - Indexed fuel prices by station ID for quick lookup
- `_stationMarkers` - Rendered map markers (expensive to regenerate)
- `_selectedFuel` - Active fuel type filter (affects marker colors and visibility)
- `_routePoints` / `_hasRoute` - Navigation route being previewed

### Data Flow
1. **Startup** - `initState()` loads stations from Spanish government API via `FuelApi`
2. **User searches location** - Autocomplete predictions from Google Places, debounced by timer
3. **User selects destination** - Calls `DirectionsApi` to get route polylines
4. **Map viewport changes** - Client-side downsampling of stations based on zoom (see `_cellSizeMetersForZoom`)
5. **Filter changes** - Regenerates markers with new prices/colors, applies performance throttling via `_runWithFilterLoading`

## Critical Implementation Patterns

### Performance Optimization
- **Marker Icon Caching** - Icons are built asynchronously and cached by color to avoid regenerating
- **Viewport-based Filtering** - Stations filtered by zoom level to prevent rendering thousands of markers
- **Route Point Downsampling** - Long routes sampled to 350 points max (see `_sampleRoute`)
- **Filter Debouncing** - Min 300ms delay before applying filter UI updates to avoid jank

### Price Color System
The `price_color.dart` utility maps prices to HSL hues (0-360°). The algorithm:
- Calculates min/max prices from filtered stations
- Maps price to hue bucket (10° increments) 
- Creates marker icons with color background + white price label text

### Geolocation & Time-based Dark Mode
- On first load and periodically, calculates sunrise/sunset via `SunTimesApi` 
- If current time is between sunset-sunrise, applies dark map style from `assets/map_style_dark.json`
- Automatically adjusts when platform brightness changes

### Tutorial System
- First-time users see onboarding via `_TutorialOverlay` widget
- Uses `GlobalKey` references to highlight UI elements (search, filter, map areas)
- State tracked in SharedPreferences with key `onboarding_seen`

## Build & Deployment

### Flutter Commands
```bash
flutter pub get          # Install dependencies
flutter run              # Debug mode (watch for changes)
flutter build apk        # Android release
flutter build ios        # iOS release
flutter build web        # Web build
```

### Key Configuration
- **Android** - See `android/app/build.gradle.kts` for signing and release config
- **iOS** - See `ios/Runner.xcodeproj` for code signing
- **App Icon** - Generated from `assets/icon/logo.png` via `flutter_launcher_icons`
- **Splash Screen** - Managed by `flutter_native_splash` plugin

## Common Workflows

### Adding a New Fuel Type
1. Add `_FuelOption` to `_fuelOptions` list in main.dart
2. Update `FuelApi._extractPrices()` if API field name differs (see regex parsing)
3. Update UI labels in bottom sheet (StationSheet widget)

### Modifying Map Marker Colors
Edit `price_color.dart` - it returns Color objects based on hue. Modify the HSL-to-RGB conversion logic.

### Debugging Station Data
- Check `_stationFuelPrices` map structure: `Map<String, Map<FuelOptionId, double>>`
- Use `Station.bestPrice` and `Station.bestFuelLabel` getters for debugging
- API response parsing happens in `FuelApi._parseDouble()` which handles Spanish locale (commas as decimals)

## External Dependencies & Keys
- **Google Maps** - Key required in iOS/Android configs
- **Google Places** - API key in `lib/services/places_key.dart` (DO NOT COMMIT)
- **Spain Fuel API** - Public endpoint, no auth needed
- **Location Services** - Requires permissions; code handles iOS/Android gracefully

## Testing & Error Handling
- Network errors caught in `_loadStations()` with user-facing SnackBar messages
- Location permission denials handled with prompts, not crashes
- Empty API responses show error state via `_ErrorState` widget
- No unit tests currently in `test/` directory - focus on integration testing via `flutter drive`

## Conventions
- **Naming** - Private members use underscore prefix (Dart style)
- **Async** - All API calls wrapped with `if (!mounted)` checks before setState()
- **Localization** - Spanish string literals throughout; no i18n framework used yet
- **State Organization** - Group by feature/concern within large state class rather than extracting widgets (avoid premature fragmentation)
