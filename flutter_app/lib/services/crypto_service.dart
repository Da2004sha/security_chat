import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class CryptoService {
  CryptoService._();
  static final CryptoService instance = CryptoService._();

  final _x25519 = X25519();
  final _ed25519 = Ed25519();
  final _hkdf = Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  );
  final _aead = AesGcm.with256bits();

  Uint8List randomBytes(int length) {
    final bytes = Uint8List(length);
    final r = Random.secure();
    for (int i = 0; i < length; i++) {
      bytes[i] = r.nextInt(256);
    }
    return bytes;
  }

  Future<(String, String)> generateDeviceKeypair() async {
    final kp = await _x25519.newKeyPair();
    final priv = await kp.extractPrivateKeyBytes();
    final pub = (await kp.extractPublicKey()).bytes;
    return (base64Encode(priv), base64Encode(pub));
  }

  Future<(String, String)> generateSigningKeypair() async {
    final kp = await _ed25519.newKeyPair();
    final priv = await kp.extractPrivateKeyBytes();
    final pub = (await kp.extractPublicKey()).bytes;
    return (base64Encode(priv), base64Encode(pub));
  }

  Future<String> signMessageEnvelope({
    required String payloadJson,
    required int chatId,
    required int senderDeviceId,
    required String privateKeyB64,
  }) async {
    final seed = base64Decode(privateKeyB64);
    final keyPair = await _ed25519.newKeyPairFromSeed(seed);
    final signature = await _ed25519.sign(
      _messageEnvelopeBytes(
        payloadJson: payloadJson,
        chatId: chatId,
        senderDeviceId: senderDeviceId,
      ),
      keyPair: keyPair,
    );
    return base64Encode(signature.bytes);
  }

  Future<bool> verifyMessageEnvelope({
    required String payloadJson,
    required int chatId,
    required int senderDeviceId,
    required String signatureB64,
    required String publicKeyB64,
  }) async {
    try {
      final signature = Signature(
        base64Decode(signatureB64),
        publicKey: SimplePublicKey(
          base64Decode(publicKeyB64),
          type: KeyPairType.ed25519,
        ),
      );
      return _ed25519.verify(
        _messageEnvelopeBytes(
          payloadJson: payloadJson,
          chatId: chatId,
          senderDeviceId: senderDeviceId,
        ),
        signature: signature,
      );
    } catch (_) {
      return false;
    }
  }

  Uint8List _messageEnvelopeBytes({
    required String payloadJson,
    required int chatId,
    required int senderDeviceId,
  }) {
    final body = 'secure_corp_chat:msg:v1|chat:$chatId|device:$senderDeviceId|payload:$payloadJson';
    return Uint8List.fromList(utf8.encode(body));
  }

  Future<Uint8List> deriveChatKey({
    required String myPrivB64,
    required String myPubB64,
    required String theirPubB64,
    required String chatContext,
  }) async {
    final myPriv = base64Decode(myPrivB64);
    final theirPubBytes = base64Decode(theirPubB64);

    if (myPriv.length != 32) {
      throw Exception('X25519 private key must be 32 bytes');
    }
    if (theirPubBytes.length != 32) {
      throw Exception('X25519 public key must be 32 bytes');
    }

    final myKeyPair = await _x25519.newKeyPairFromSeed(myPriv);
    final theirPub = SimplePublicKey(theirPubBytes, type: KeyPairType.x25519);

    final shared = await _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: theirPub,
    );
    final sharedBytes = await shared.extractBytes();

    final myPubBytes = base64Decode(myPubB64);
    final (pMin, pMax) = _lexicographicMinMax(myPubBytes, theirPubBytes);

    final info = Uint8List.fromList([
      ...utf8.encode('secure_corp_chat:v2|'),
      ...utf8.encode(chatContext),
      ...utf8.encode('|pubmin:'),
      ...pMin,
      ...utf8.encode('|pubmax:'),
      ...pMax,
    ]);

    final okm = await _hkdf.deriveKey(
      secretKey: SecretKey(sharedBytes),
      info: info,
      nonce: Uint8List(0),
    );

    final keyBytes = await okm.extractBytes();
    return Uint8List.fromList(keyBytes);
  }

  Future<String> encryptJson({
    required Map<String, dynamic> plaintext,
    required Uint8List key,
    required String aad,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(plaintext)));
    final packedBytes = await encryptBytes(
      plaintext: bytes,
      key: key,
      aad: aad,
    );
    return base64Encode(packedBytes);
  }

  Future<Map<String, dynamic>> decryptJson({
    required String payloadJson,
    required Uint8List key,
  }) async {
    final packedBytes = base64Decode(payloadJson);
    final plainBytes = await decryptBytes(
      packedJsonBytes: packedBytes,
      key: key,
    );
    return (jsonDecode(utf8.decode(plainBytes)) as Map).cast<String, dynamic>();
  }

  Future<Uint8List> encryptBytes({
    required Uint8List plaintext,
    required Uint8List key,
    required String aad,
  }) async {
    if (key.length != 32) {
      throw Exception('AES-256 key must be 32 bytes');
    }

    final nonce = _randomBytes(12);
    final secretKey = SecretKey(key);

    final box = await _aead.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
      aad: utf8.encode(aad),
    );

    final packed = <String, dynamic>{
      'v': 2,
      'algo': 'aesgcm256',
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
      'aad': aad,
    };

    return Uint8List.fromList(utf8.encode(jsonEncode(packed)));
  }

  Future<Uint8List> decryptBytes({
    required Uint8List packedJsonBytes,
    required Uint8List key,
  }) async {
    if (key.length != 32) {
      throw Exception('AES-256 key must be 32 bytes');
    }

    final packedStr = utf8.decode(packedJsonBytes);
    final packed = (jsonDecode(packedStr) as Map).cast<String, dynamic>();

    final algo = packed['algo'] as String?;
    if (algo != 'aesgcm256') {
      throw Exception('Unsupported algo: $algo');
    }

    final nonce = base64Decode(packed['nonce'] as String);
    final cipher = base64Decode(packed['ciphertext'] as String);
    final mac = Mac(base64Decode(packed['mac'] as String));
    final aad = (packed['aad'] as String?) ?? '';

    final box = SecretBox(cipher, nonce: nonce, mac: mac);

    final plain = await _aead.decrypt(
      box,
      secretKey: SecretKey(key),
      aad: utf8.encode(aad),
    );

    return Uint8List.fromList(plain);
  }

  Uint8List _randomBytes(int n) {
    final r = Random.secure();
    final out = Uint8List(n);
    for (int i = 0; i < n; i++) {
      out[i] = r.nextInt(256);
    }
    return out;
  }

  (Uint8List, Uint8List) _lexicographicMinMax(Uint8List a, Uint8List b) {
    final len = min(a.length, b.length);
    for (int i = 0; i < len; i++) {
      if (a[i] < b[i]) return (a, b);
      if (a[i] > b[i]) return (b, a);
    }
    return (a.length <= b.length) ? (a, b) : (b, a);
  }
}
