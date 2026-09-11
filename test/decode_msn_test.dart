import 'package:flutter_test/flutter_test.dart';
import 'package:overmorrow/decoders/decode_msn.dart';
import 'package:overmorrow/l10n/app_localizations_en.dart';
import 'package:overmorrow/services/weather_service.dart';
import 'package:xml/xml.dart';
void main() {
  group('MSN Weather Decoder Tests', () {
    test('msnMapSkyCodeToCondition maps codes correctly', () {
      expect(msnMapSkyCodeToCondition(32), 'Clear Sky');
      expect(msnMapSkyCodeToCondition(32, isNight: true), 'Clear Night');
      expect(msnMapSkyCodeToCondition(31), 'Clear Night');
      expect(msnMapSkyCodeToCondition(34), 'Clear Sky');
      expect(msnMapSkyCodeToCondition(26), 'Overcast');
      expect(msnMapSkyCodeToCondition(28), 'Partly Cloudy');
      expect(msnMapSkyCodeToCondition(27, isNight: true), 'Cloudy Night');
      expect(msnMapSkyCodeToCondition(11), 'Rain');
      expect(msnMapSkyCodeToCondition(9), 'Drizzle');
      expect(msnMapSkyCodeToCondition(4), 'Thunderstorm');
      expect(msnMapSkyCodeToCondition(16), 'Snow');
      expect(msnMapSkyCodeToCondition(42), 'Heavy Snow');
      expect(msnMapSkyCodeToCondition(7), 'Sleet');
      expect(msnMapSkyCodeToCondition(20), 'Fog');
      expect(msnMapSkyCodeToCondition(21), 'Haze');
    });

    test('XML parser parses MSN Weather XML format accurately', () {
      const sampleXml = '''<?xml version="1.0" ?>
<weatherdata>
  <weather weatherlocationcode="wc:VMXX0006" weatherlocationname="Hanoi, Vietnam" degreetype="C" lat="21.028" long="105.854">
    <current temperature="30" skycode="34" skytext="Mostly sunny" date="2026-09-11" observationtime="12:10:00" feelslike="35" humidity="59" windspeed="12 km/h" />
    <forecast low="24" high="31" skycodeday="34" skytextday="Mostly sunny" date="2026-09-11" day="Friday" precip="12" />
    <forecast low="25" high="32" skycodeday="34" skytextday="Mostly sunny" date="2026-09-12" day="Saturday" precip="1" />
    <forecast low="24" high="29" skycodeday="9" skytextday="Light rain" date="2026-09-13" day="Sunday" precip="68" />
  </weather>
</weatherdata>''';

      final doc = XmlDocument.parse(sampleXml);
      final weatherElement = doc.findAllElements('weather').first;
      final currentElement = weatherElement.findElements('current').first;
      final forecastElements = weatherElement.findElements('forecast').toList();

      expect(currentElement.getAttribute('temperature'), '30');
      expect(currentElement.getAttribute('feelslike'), '35');
      expect(currentElement.getAttribute('humidity'), '59');
      expect(currentElement.getAttribute('windspeed'), '12 km/h');
      expect(currentElement.getAttribute('skycode'), '34');

      expect(forecastElements.length, 3);
      expect(forecastElements[0].getAttribute('low'), '24');
      expect(forecastElements[0].getAttribute('high'), '31');
      expect(forecastElements[0].getAttribute('precip'), '12');

      expect(forecastElements[2].getAttribute('skycodeday'), '9');
      expect(msnMapSkyCodeToCondition(int.parse(forecastElements[2].getAttribute('skycodeday')!)), 'Drizzle');
    });

    test('getRain15MinuteLocalization handles empty and unknown keys defensively', () {
      final loc = AppLocalizationsEn();
      expect(getRain15MinuteLocalization('', 0, loc), '');
      expect(getRain15MinuteLocalization('MSN Weather Service', 60, loc), '');
      expect(getRain15MinuteLocalization('rainInOneHour', 1, loc), loc.rainInOneHour);
      expect(getRain15MinuteLocalization('rainExpectedInHours', 2, loc), loc.rainExpectedInHours(2));
    });
  });
}
