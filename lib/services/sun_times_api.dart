import 'dart:convert';

import 'package:http/http.dart' as http;

class SunTimesApi {
  static const _endpoint = 'https://api.sunrise-sunset.org/json';

  Future<SunTimes> fetchSunTimes(double lat, double lng) async {
    final uri = Uri.parse(_endpoint).replace(queryParameters: {
      'lat': lat.toString(),
      'lng': lng.toString(),
      'formatted': '0',
    });

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('SunTimes status ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['status']?.toString() != 'OK') {
      throw Exception('SunTimes status ${data['status']}');
    }

    final results = data['results'] as Map<String, dynamic>?;
    if (results == null) {
      throw Exception('SunTimes missing results');
    }

    final sunriseRaw = results['sunrise']?.toString();
    final sunsetRaw = results['sunset']?.toString();
    if (sunriseRaw == null || sunsetRaw == null) {
      throw Exception('SunTimes missing sunrise/sunset');
    }

    final sunrise = DateTime.parse(sunriseRaw).toUtc();
    final sunset = DateTime.parse(sunsetRaw).toUtc();
    return SunTimes(sunrise: sunrise, sunset: sunset);
  }

  bool isNight(SunTimes times, {DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();
    return current.isBefore(times.sunrise) || current.isAfter(times.sunset);
  }

  DateTime? nextTransition(SunTimes times, DateTime now) {
    final current = now.toUtc();
    if (current.isBefore(times.sunrise)) return times.sunrise;
    if (current.isBefore(times.sunset)) return times.sunset;
    return times.sunrise.add(const Duration(days: 1));
  }
}

class SunTimes {
  const SunTimes({
    required this.sunrise,
    required this.sunset,
  });

  final DateTime sunrise;
  final DateTime sunset;
}
