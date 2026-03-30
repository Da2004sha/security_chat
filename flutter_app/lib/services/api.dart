import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'session.dart';

class Api {
  Api._() {
    _client = _buildClient();
  }

  static final Api instance = Api._();

  late final http.Client _client;

  String baseUrl = 'https://eustatically-gustatory-jamar.ngrok-free.dev';

  http.Client _buildClient() {
    final ioHttpClient = HttpClient();

    ioHttpClient.badCertificateCallback =
        ((X509Certificate cert, String host, int port) => true);
    ioHttpClient.connectionTimeout = const Duration(seconds: 20);
    ioHttpClient.idleTimeout = const Duration(seconds: 20);
    ioHttpClient.userAgent = 'SecureCorpChat/1.0';

    return IOClient(ioHttpClient);
  }

  Map<String, String> _headers({required bool auth, bool json = false}) {
    return {
      if (json) 'Content-Type': 'application/json',
      'Accept': 'application/json',
      'ngrok-skip-browser-warning': 'true',
      if (auth) ...Session.instance.authHeaders(),
    };
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path');

    try {
      final res = await _client
          .post(
            uri,
            headers: _headers(auth: auth, json: true),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode >= 400) {
        throw Exception('POST $path -> ${res.statusCode}: ${res.body}');
      }

      return jsonDecode(res.body) as Map<String, dynamic>;
    } on SocketException catch (e) {
      throw Exception('POST $path failed: network error: $e');
    } on HandshakeException catch (e) {
      throw Exception('POST $path failed: TLS/SSL handshake error: $e');
    } on HttpException catch (e) {
      throw Exception('POST $path failed: http error: $e');
    } on FormatException catch (e) {
      throw Exception('POST $path failed: invalid JSON: $e');
    } catch (e) {
      throw Exception('POST $path failed: $e');
    }
  }

  Future<List<dynamic>> getList(String path, {bool auth = true}) async {
    final uri = Uri.parse('$baseUrl$path');

    try {
      final res = await _client
          .get(
            uri,
            headers: _headers(auth: auth),
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode >= 400) {
        throw Exception('GET $path -> ${res.statusCode}: ${res.body}');
      }

      return jsonDecode(res.body) as List<dynamic>;
    } on SocketException catch (e) {
      throw Exception('GET $path failed: network error: $e');
    } on HandshakeException catch (e) {
      throw Exception('GET $path failed: TLS/SSL handshake error: $e');
    } on HttpException catch (e) {
      throw Exception('GET $path failed: http error: $e');
    } on FormatException catch (e) {
      throw Exception('GET $path failed: invalid JSON: $e');
    } catch (e) {
      throw Exception('GET $path failed: $e');
    }
  }

  Future<Map<String, dynamic>> get(String path, {bool auth = true}) async {
    final uri = Uri.parse('$baseUrl$path');

    try {
      final res = await _client
          .get(
            uri,
            headers: _headers(auth: auth),
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode >= 400) {
        throw Exception('GET $path -> ${res.statusCode}: ${res.body}');
      }

      return jsonDecode(res.body) as Map<String, dynamic>;
    } on SocketException catch (e) {
      throw Exception('GET $path failed: network error: $e');
    } on HandshakeException catch (e) {
      throw Exception('GET $path failed: TLS/SSL handshake error: $e');
    } on HttpException catch (e) {
      throw Exception('GET $path failed: http error: $e');
    } on FormatException catch (e) {
      throw Exception('GET $path failed: invalid JSON: $e');
    } catch (e) {
      throw Exception('GET $path failed: $e');
    }
  }

  Future<Map<String, dynamic>> delete(String path, {bool auth = true}) async {
    final uri = Uri.parse('$baseUrl$path');

    try {
      final res = await _client
          .delete(
            uri,
            headers: _headers(auth: auth),
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode >= 400) {
        throw Exception('DELETE $path -> ${res.statusCode}: ${res.body}');
      }

      if (res.body.isEmpty) {
        return <String, dynamic>{};
      }

      return jsonDecode(res.body) as Map<String, dynamic>;
    } on SocketException catch (e) {
      throw Exception('DELETE $path failed: network error: $e');
    } on HandshakeException catch (e) {
      throw Exception('DELETE $path failed: TLS/SSL handshake error: $e');
    } on HttpException catch (e) {
      throw Exception('DELETE $path failed: http error: $e');
    } on FormatException catch (e) {
      throw Exception('DELETE $path failed: invalid JSON: $e');
    } catch (e) {
      throw Exception('DELETE $path failed: $e');
    }
  }

  Uri uri(String path) => Uri.parse('$baseUrl$path');
}