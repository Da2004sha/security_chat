import 'dart:convert';
import 'package:http/http.dart' as http;
import 'session.dart';

class Api {
  Api._();
  static final Api instance = Api._();

  String baseUrl = "http://192.168.0.107:8001";

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    final uri = Uri.parse("$baseUrl$path");
    final headers = {
      "Content-Type": "application/json",
      if (auth) ...Session.instance.authHeaders(),
    };
    final res = await http.post(uri, headers: headers, body: jsonEncode(body));
    if (res.statusCode >= 400) {
      throw Exception("${res.statusCode}: ${res.body}");
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> getList(String path, {bool auth = true}) async {
    final uri = Uri.parse("$baseUrl$path");
    final headers = {
      if (auth) ...Session.instance.authHeaders(),
    };
    final res = await http.get(uri, headers: headers);
    if (res.statusCode >= 400) {
      throw Exception("${res.statusCode}: ${res.body}");
    }
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> get(String path, {bool auth = true}) async {
    final uri = Uri.parse("$baseUrl$path");
    final headers = {
      if (auth) ...Session.instance.authHeaders(),
    };
    final res = await http.get(uri, headers: headers);
    if (res.statusCode >= 400) {
      throw Exception("${res.statusCode}: ${res.body}");
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> delete(String path, {bool auth = true}) async {
    final uri = Uri.parse("$baseUrl$path");
    final headers = {
      if (auth) ...Session.instance.authHeaders(),
    };
    final res = await http.delete(uri, headers: headers);
    if (res.statusCode >= 400) {
      throw Exception("${res.statusCode}: ${res.body}");
    }
    if (res.body.isEmpty) {
      return <String, dynamic>{};
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Uri uri(String path) => Uri.parse("$baseUrl$path");
}