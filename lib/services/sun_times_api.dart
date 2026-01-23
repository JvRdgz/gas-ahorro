import 'dart:convert';

import 'package:http/http.dart' as http;

class SunTimesApi {
  static const _endpoint = 'https://api.sunrise-sunset.org/json';

  Future<bool?> isNight({
    required double lat,
    required double lng,
  }) async {
    final uri = Uri.parse(_endpoint).replace(queryParameters: {
      'lat': lat.toString(),
      'lng': lng.toString(),
      'formatted': '0',
    });

    final response = await http.get(uri);
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['status']?.toString() != 'OK') return null;

    final results = data['results'] as Map<String, dynamic>?;
    if (results == null) return null;

    final sunriseRaw = results['sunrise']?.toString();
    final sunsetRaw = results['sunset']?.toString();
    if (sunriseRaw == null || sunsetRaw == null) return null;

    final sunrise = DateTime.parse(sunriseRaw).toUtc();
    final sunset = DateTime.parse(sunsetRaw).toUtc();
    final now = DateTime.now().toUtc();

    return now.isBefore(sunrise) || now.isAfter(sunset);
  }
}
