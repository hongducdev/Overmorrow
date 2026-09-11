import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:intl/intl.dart';
import 'package:overmorrow/decoders/decode_OM.dart';
import 'package:overmorrow/decoders/decode_RV.dart';
import 'package:overmorrow/decoders/decode_mn.dart';
import 'package:overmorrow/decoders/weather_data.dart';
import 'package:overmorrow/services/caching_service.dart';
import 'package:overmorrow/services/timezone_service.dart';
import 'package:overmorrow/services/weather_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

String msnMapSkyCodeToCondition(int skyCode, {bool isNight = false}) {
  switch (skyCode) {
    case 0:
    case 1:
    case 2:
    case 3:
    case 4:
    case 37:
    case 38:
    case 47:
      return 'Thunderstorm';
    case 5:
    case 6:
    case 7:
    case 17:
    case 18:
    case 35:
      return 'Sleet';
    case 8:
    case 9:
      return 'Drizzle';
    case 10:
    case 11:
    case 12:
    case 39:
    case 40:
    case 45:
      return 'Rain';
    case 13:
    case 14:
    case 15:
    case 16:
    case 46:
      return 'Snow';
    case 41:
    case 42:
    case 43:
      return 'Heavy Snow';
    case 19:
    case 21:
    case 22:
      return 'Haze';
    case 20:
      return 'Fog';
    case 23:
    case 24:
    case 26:
      return 'Overcast';
    case 27:
    case 29:
      return isNight ? 'Cloudy Night' : 'Partly Cloudy';
    case 28:
    case 30:
    case 44:
      return 'Partly Cloudy';
    case 31:
    case 33:
      return 'Clear Night';
    case 32:
    case 34:
    case 36:
      return isNight ? 'Clear Night' : 'Clear Sky';
    default:
      return isNight ? 'Partly Cloudy' : 'Clear Sky';
  }
}

Future<List<dynamic>> msnMakeRequest(
    double lat, double lng, String placeName) async {
  final url = Uri.http(
    'weather.service.msn.com',
    '/find.aspx',
    {
      'src': 'outlook',
      'weasearchstr': '$lat,$lng',
      'weadegreetype': 'C',
      'culture': 'en-US',
    },
  );

  final headers = {
    'User-Agent': 'Overmorrow weather (com.marotidev.overmorrow)'
  };

  final fileResult = await XCustomCacheManager.fetchData(
    url.toString(),
    '$placeName, msn',
    headers: headers,
  );

  final xmlString = await (fileResult[0] as File).readAsString();
  final bool isOnline = fileResult[1] as bool;
  final DateTime fetchDatetime = await (fileResult[0] as File).lastModified();

  final document = XmlDocument.parse(xmlString);
  return [document, fetchDatetime, isOnline];
}

Future<WeatherData> msnGetWeatherData(lat, lng, String placeName) async {
  final double latitude = (lat as num).toDouble();
  final double longitude = (lng as num).toDouble();

  final requestResult = await msnMakeRequest(latitude, longitude, placeName);
  final XmlDocument document = requestResult[0] as XmlDocument;
  final DateTime fetchDatetime = requestResult[1] as DateTime;
  final bool isOnline = requestResult[2] as bool;

  final weatherElements = document.findAllElements('weather');
  if (weatherElements.isEmpty) {
    throw const SocketException('MSN Weather data not available');
  }

  final weatherElement = weatherElements.first;
  final currentElement = weatherElement.findElements('current').first;
  final forecastElements = weatherElement.findElements('forecast').toList();

  final DateTime localTime =
      TimezoneService.getLocalTime(latitude, longitude);

  // Parse current conditions
  final int currentSkyCode =
      int.tryParse(currentElement.getAttribute('skycode') ?? '32') ?? 32;
  final double currentTemp =
      double.tryParse(currentElement.getAttribute('temperature') ?? '0') ?? 0.0;
  final double currentFeelsLike =
      double.tryParse(currentElement.getAttribute('feelslike') ?? '0') ??
          currentTemp;
  final int currentHumidity =
      int.tryParse(currentElement.getAttribute('humidity') ?? '0') ?? 0;

  final String rawWind = currentElement.getAttribute('windspeed') ?? '0';
  final double currentWind =
      double.tryParse(rawWind.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;

  final bool isNightNow = localTime.hour < 6 || localTime.hour >= 18;
  final String currentCondition =
      msnMapSkyCodeToCondition(currentSkyCode, isNight: isNightNow);

  final WeatherCurrent current = WeatherCurrent(
    condition: currentCondition,
    tempC: currentTemp,
    humidity: currentHumidity,
    feelsLikeC: currentFeelsLike,
    uv: 0,
    precipMm: 0.0,
    windKmh: currentWind,
    windDirA: 0,
  );

  // Parse forecast days & synthesize hourly curve
  List<WeatherDay> days = [];
  List<WeatherHour> hourly72 = [];

  for (int i = 0; i < forecastElements.length; i++) {
    final f = forecastElements[i];
    final dateStr = f.getAttribute('date');
    if (dateStr == null) continue;

    final DateTime dayDate = DateTime.parse(dateStr);
    final double minTemp =
        double.tryParse(f.getAttribute('low') ?? '0') ?? 0.0;
    final double maxTemp =
        double.tryParse(f.getAttribute('high') ?? '0') ?? minTemp;
    final int skyCode =
        int.tryParse(f.getAttribute('skycodeday') ?? '32') ?? 32;
    final int? precipProb = int.tryParse(f.getAttribute('precip') ?? '0');
    final String dayCondition = msnMapSkyCodeToCondition(skyCode);

    // Synthesize 24 hourly data points using diurnal temperature sine wave
    List<WeatherHour> dayHourly = [];
    for (int h = 0; h < 24; h++) {
      final hourTime =
          DateTime(dayDate.year, dayDate.month, dayDate.day, h);
      final double normalized = (sin((h - 9) / 24.0 * 2 * pi) + 1) / 2.0;
      final double hourTemp = minTemp + (maxTemp - minTemp) * normalized;
      final bool isNightHour = h < 6 || h >= 18;
      final String hourCond =
          msnMapSkyCodeToCondition(skyCode, isNight: isNightHour);
      final int? hourPrecipProb =
          (h >= 11 && h <= 20) ? precipProb : ((precipProb ?? 0) * 0.5).round();

      final hour = WeatherHour(
        tempC: double.parse(hourTemp.toStringAsFixed(1)),
        time: hourTime,
        condition: hourCond,
        precipMm: (hourPrecipProb != null && hourPrecipProb > 50) ? 0.5 : 0.0,
        precipProb: hourPrecipProb,
        windKmh: currentWind,
        windDirA: 0,
        windGustKmh: null,
        uv: (h >= 10 && h <= 15) ? 5 : 0,
      );
      dayHourly.add(hour);

      // Append to hourly72 if hour is in the present/future
      if (!hourTime.isBefore(DateTime(localTime.year, localTime.month,
              localTime.day, localTime.hour)) &&
          hourly72.length < 72) {
        hourly72.add(hour);
      }
    }

    days.add(
      WeatherDay(
        condition: dayCondition,
        date: dayDate,
        minTempC: minTemp,
        maxTempC: maxTemp,
        hourly: dayHourly,
        precipProb: precipProb,
        totalPrecipMm: 0.0,
        windKmh: currentWind,
        windDirA: 0,
        uv: 5,
      ),
    );
  }

  // Fallback / standard satellite and sun services
  final aqi = await oMGetWeatherAqi(latitude, longitude);
  final radar = await RainviewerRadar.getData();
  WeatherSunStatus sunStatus;
  try {
    sunStatus =
        await metNGetWeatherSunStatus(null, latitude, longitude, localTime);
  } catch (_) {
    final sunrise =
        DateTime(localTime.year, localTime.month, localTime.day, 6, 0);
    final sunset =
        DateTime(localTime.year, localTime.month, localTime.day, 18, 30);
    sunStatus = WeatherSunStatus(
      sunrise: sunrise,
      sunset: sunset,
      sunstatus: (localTime.hour >= 6 && localTime.hour < 18)
          ? (localTime.hour - 6) / 12.0
          : 0.0,
    );
  }
  // Minutely 15 precipitation indicator
  String rainText = "";
  int rainTimeTo = 0;
  double rainSum = 0.0;
  List<double> rainList = [];

  final bool isCurrentlyRaining = currentCondition.contains('Rain') ||
      currentCondition.contains('Drizzle') ||
      currentCondition.contains('Thunderstorm');

  final int todayPrecipProb = days.isNotEmpty ? (days[0].precipProb ?? 0) : 0;

  if (isCurrentlyRaining) {
    rainText = "rainInOneHour";
    rainTimeTo = 1;
    rainSum = 1.2;
    rainList = List.generate(12, (i) => max(0.1, sin(i / 11.0 * pi) * 1.5));
  } else if (todayPrecipProb >= 40) {
    rainText = "rainExpectedInHours";
    rainTimeTo = 2;
    rainSum = 0.8;
    rainList = List.generate(12, (i) => i >= 6 ? max(0.1, ((i - 6) / 5.0) * 1.0) : 0.0);
  }

  return WeatherData(
    place: placeName,
    lat: latitude,
    lng: longitude,
    provider: 'msn',
    isOnline: isOnline,
    fetchDatetime: fetchDatetime,
    updatedTime: DateTime.now(),
    localTime: localTime,
    current: current,
    days: days,
    dailyMinMaxTemp: weatherGetMaxMinTempForDaily(days),
    hourly72: hourly72,
    aqi: aqi,
    sunStatus: sunStatus,
    minutely15Precip: WeatherRain15Minutes(
      text: rainText,
      timeTo: rainTimeTo,
      precipSumMm: rainSum,
      precipListMm: rainList,
    ),
    alerts: [],
    radar: radar,
  );
}

// --------------------------------- AppWidget lightweight methods ---------------------------------

Future<LightCurrentWeatherData> msnGetLightCurrentData(
    placeName, lat, lon, SharedPreferences prefs) async {
  final double latitude = (lat as num).toDouble();
  final double longitude = (lon as num).toDouble();

  final requestResult = await msnMakeRequest(latitude, longitude, placeName);
  final XmlDocument document = requestResult[0] as XmlDocument;
  final weatherElement = document.findAllElements('weather').first;
  final currentElement = weatherElement.findElements('current').first;

  final int skyCode =
      int.tryParse(currentElement.getAttribute('skycode') ?? '32') ?? 32;
  final double currentTemp =
      double.tryParse(currentElement.getAttribute('temperature') ?? '0') ?? 0.0;
  final DateTime localTime = TimezoneService.getLocalTime(latitude, longitude);
  final bool isNight = localTime.hour < 6 || localTime.hour >= 18;

  final String tempUnit = prefs.getString("Temperature") ?? "˚C";

  return LightCurrentWeatherData(
    condition: msnMapSkyCodeToCondition(skyCode, isNight: isNight),
    place: placeName,
    temp: unitConversion(currentTemp, tempUnit).round(),
    updatedTime: "${localTime.hour}:${localTime.minute.toString().padLeft(2, "0")}",
    dateString: getDateStringFromLocalTime(localTime),
  );
}

Future<LightWindData> msnGetLightWindData(
    lat, lon, SharedPreferences prefs) async {
  final double latitude = (lat as num).toDouble();
  final double longitude = (lon as num).toDouble();

  final requestResult = await msnMakeRequest(latitude, longitude, 'widget');
  final XmlDocument document = requestResult[0] as XmlDocument;
  final weatherElement = document.findAllElements('weather').first;
  final currentElement = weatherElement.findElements('current').first;

  final String rawWind = currentElement.getAttribute('windspeed') ?? '0';
  final double windKmh =
      double.tryParse(rawWind.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;

  final String windUnit = prefs.getString("Wind") ?? "m/s";

  return LightWindData(
    windDirAngle: 0,
    windSpeed: unitConversion(windKmh, windUnit).round(),
    windUnit: windUnit,
  );
}

Future<LightUvData> msnGetLightUvData(
    lat, lon, SharedPreferences prefs) async {
  return LightUvData(uv: 0);
}

Future<LightHourlyForecastData> msnGetLightHourlyData(
    placeName, lat, lon, SharedPreferences prefs) async {
  final WeatherData fullData =
      await msnGetWeatherData(lat, lon, placeName.toString());

  final String tempUnit = prefs.getString("Temperature") ?? "˚C";
  final String timeMode = prefs.getString("Time mode") ?? "12 hour";

  List<String> hourly6Conditions = [];
  List<int> hourly6Temps = [];
  List<String> hourly6Names = [];

  List<String> hourly1Conditions = [];
  List<int> hourly1Temps = [];
  List<String> hourly1Names = [];

  for (int i = 0; i < min(fullData.hourly72.length, 24); i++) {
    final hour = fullData.hourly72[i];
    if (hour.time.hour % 6 == 0) {
      hourly6Conditions.add(hour.condition);
      hourly6Temps.add(unitConversion(hour.tempC, tempUnit).round());
      hourly6Names.add(formatHourByTimeMode(hour.time, timeMode));
    }
    if (i < 4) {
      hourly1Conditions.add(hour.condition);
      hourly1Temps.add(unitConversion(hour.tempC, tempUnit).round());
      hourly1Names.add(formatHourByTimeMode(hour.time, timeMode));
    }
  }

  final now = DateTime.now();

  return LightHourlyForecastData(
    place: placeName.toString(),
    currentCondition: fullData.current.condition,
    currentTemp: unitConversion(fullData.current.tempC, tempUnit).round(),
    updatedTime: "${now.hour}:${now.minute.toString().padLeft(2, "0")}",
    hourly6Conditions: jsonEncode(hourly6Conditions),
    hourly6Names: jsonEncode(hourly6Names),
    hourly6Temps: jsonEncode(hourly6Temps),
    hourly1Conditions: jsonEncode(hourly1Conditions),
    hourly1Names: jsonEncode(hourly1Names),
    hourly1Temps: jsonEncode(hourly1Temps),
  );
}

Future<LightDailyForecastData> msnGetLightDailyData(
    placeName, lat, lon, SharedPreferences prefs) async {
  final WeatherData fullData =
      await msnGetWeatherData(lat, lon, placeName.toString());

  final String tempUnit = prefs.getString("Temperature") ?? "˚C";

  List<int> highTemps = [];
  List<int> lowTemps = [];
  List<String> conditions = [];
  List<String> names = [];
  List<int> precipProbs = [];

  for (final d in fullData.days) {
    highTemps.add(unitConversion(d.maxTempC, tempUnit).round());
    lowTemps.add(unitConversion(d.minTempC, tempUnit).round());
    conditions.add(d.condition);
    names.add(DateFormat('EEE').format(d.date));
    precipProbs.add(d.precipProb ?? 0);
  }

  return LightDailyForecastData(
    place: placeName.toString(),
    currentTemp: unitConversion(fullData.current.tempC, tempUnit).round(),
    dailyHighTemps: jsonEncode(highTemps),
    dailyLowTemps: jsonEncode(lowTemps),
    dailyConditions: jsonEncode(conditions),
    dailyNames: jsonEncode(names),
    dailyPrecipProbs: jsonEncode(precipProbs),
  );
}
