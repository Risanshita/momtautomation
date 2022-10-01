import 'package:json_annotation/json_annotation.dart';
import 'dart:convert';

@JsonSerializable()
class WeatherForecast {
  DateTime? date;
  int? temperatureC;
  int? temperatureF;
  String? summary;

  WeatherForecast(
      this.date, this.temperatureC, this.temperatureF, this.summary);

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'date': date?.millisecondsSinceEpoch,
      'temperatureC': temperatureC,
      'temperatureF': temperatureF,
      'summary': summary,
    };
  }

  factory WeatherForecast.fromMap(Map<String, dynamic> map) {
    return WeatherForecast(
      map['date'] != null ? DateTime.parse(map['date']) : null,
      map['temperatureC'] != null ? map['temperatureC'] as int : null,
      map['temperatureF'] != null ? map['temperatureF'] as int : null,
      map['summary'] != null ? map['summary'] as String : null,
    );
  }

  String toJson() => json.encode(toMap());

  factory WeatherForecast.fromJson(String source) =>
      WeatherForecast.fromMap(json.decode(source) as Map<String, dynamic>);
}
