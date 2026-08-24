class AppConfig {
  static const String appName = "RailNova";

  // Android Emulator = http://10.0.2.2:5000/api
  // Real Phone = http://<apne PC ka IP>:5000/api (e.g. http://192.168.1.5:5000/api)
  // Chrome / Desktop = http://localhost:5000/api
  static const String baseUrl = "https://railnovaa.onrender.com/api";

  static const Duration apiTimeout = Duration(seconds: 30);
}