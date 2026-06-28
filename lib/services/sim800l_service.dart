import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class Sim800lService {
  // ⚠️  Replace with your Arduino's IP address and port
  static const String _baseUrl = 'http://YOUR_ARDUINO_IP:8080';
  // Example: 'http://192.168.1.100:8080'

  /// Send an SMS to a phone number via the Arduino SIM800L module
  Future<bool> sendSMS(String phoneNumber, String message) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/sms'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phoneNumber,
          'message': message,
        }),
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('SMS Error: $e');
      return false;
    }
  }

  /// Check if the Arduino/SIM800L module is online
  Future<bool> checkStatus() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/status'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
