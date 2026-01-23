import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/place_prediction.dart';
import 'places_key.dart';

class PlacesApi {
  static const _autocompleteEndpoint =
      'https://maps.googleapis.com/maps/api/place/autocomplete/json';
  static const _detailsEndpoint =
      'https://maps.googleapis.com/maps/api/place/details/json';

  Future<List<PlacePrediction>> autocomplete({
    required String input,
    required String sessionToken,
  }) async {
    if (googleMapsApiKey.isEmpty) {
      throw Exception('GOOGLE_MAPS_API_KEY no configurada.');
    }

    final uri = Uri.parse(_autocompleteEndpoint).replace(queryParameters: {
      'input': input,
      'key': googleMapsApiKey,
      'language': 'es',
      'components': 'country:es',
      'sessiontoken': sessionToken,
    });

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Error en Autocomplete (${response.statusCode}).');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final status = data['status']?.toString();
    if (status != 'OK' && status != 'ZERO_RESULTS') {
      throw Exception('Autocomplete status: $status');
    }

    final predictions = data['predictions'] as List<dynamic>? ?? [];
    return predictions.map((raw) {
      final item = raw as Map<String, dynamic>;
      final structured = item['structured_formatting'] as Map<String, dynamic>? ?? {};
      return PlacePrediction(
        placeId: item['place_id']?.toString() ?? '',
        description: item['description']?.toString() ?? '',
        primaryText: structured['main_text']?.toString() ?? '',
        secondaryText: structured['secondary_text']?.toString() ?? '',
      );
    }).where((p) => p.placeId.isNotEmpty).toList();
  }

  Future<Map<String, double>> fetchPlaceLocation({
    required String placeId,
    required String sessionToken,
  }) async {
    if (googleMapsApiKey.isEmpty) {
      throw Exception('GOOGLE_MAPS_API_KEY no configurada.');
    }

    final uri = Uri.parse(_detailsEndpoint).replace(queryParameters: {
      'place_id': placeId,
      'key': googleMapsApiKey,
      'fields': 'geometry/location',
      'language': 'es',
      'sessiontoken': sessionToken,
    });

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Error en Place Details (${response.statusCode}).');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final status = data['status']?.toString();
    if (status != 'OK') {
      throw Exception('Place Details status: $status');
    }

    final location = data['result']?['geometry']?['location'] as Map<String, dynamic>?;
    if (location == null) {
      throw Exception('Sin coordenadas para el lugar.');
    }

    final lat = (location['lat'] as num).toDouble();
    final lng = (location['lng'] as num).toDouble();
    return {'lat': lat, 'lng': lng};
  }
}
