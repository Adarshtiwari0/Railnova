class Station {
  final String code;
  final String name;
  final String city;

  const Station({required this.code, required this.name, required this.city});

  factory Station.fromJson(Map<String, dynamic> json) {
    return Station(
      code: (json["station_code"] ?? json["stnCode"] ?? "").toString(),
      name: (json["station_name"] ?? json["stnName"] ?? "").toString(),
      city: (json["station_city"] ?? json["stnCity"] ?? "").toString(),
    );
  }
}
