import 'dart:convert';

import 'package:http/http.dart' as http;

import 'session.dart';

class Api {
  Api._();

  static final Api instance = Api._();

  final http.Client _client = http.Client();

  String baseUrl = 'https://securitychat-production.up.railway.app';

  Map<String, String> _headers({required bool auth, bool json = false}) {
    return {
      if (json) 'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (auth) ...Session.instance.authHeaders(),
    };
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path');

    final res = await _client.post(
      uri,
      headers: _headers(auth: auth, json: true),
      body: jsonEncode(body),
    );

    if (res.statusCode >= 400) {
      throw Exception('POST $path -> ${res.statusCode}: ${res.body}');
    }

    return jsonDecode(res.body);
  }

  Future<List<dynamic>> getList(String path, {bool auth = true}) async {
    final uri = Uri.parse('$baseUrl$path');

    final res = await _client.get(
      uri,
      headers: _headers(auth: auth),
    );

    if (res.statusCode >= 400) {
      throw Exception('GET $path -> ${res.statusCode}: ${res.body}');
    }

    return jsonDecode(res.body);
  }

  Future<Map<String, dynamic>> get(String path, {bool auth = true}) async {
    final uri = Uri.parse('$baseUrl$path');

    final res = await _client.get(
      uri,
      headers: _headers(auth: auth),
    );

    if (res.statusCode >= 400) {
      throw Exception('GET $path -> ${res.statusCode}: ${res.body}');
    }

    return jsonDecode(res.body);
  }

  Future<Map<String, dynamic>> delete(String path, {bool auth = true}) async {
    final uri = Uri.parse('$baseUrl$path');

    final res = await _client.delete(
      uri,
      headers: _headers(auth: auth),
    );

    if (res.statusCode >= 400) {
      throw Exception('DELETE $path -> ${res.statusCode}: ${res.body}');
    }

    if (res.body.isEmpty) return {};

    return jsonDecode(res.body);
  }

  Uri uri(String path) => Uri.parse('$baseUrl$path');
}