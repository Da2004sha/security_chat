# Secure Corporate Chat (Flutter + FastAPI) — working E2EE MVP

This repository contains:
- `backend/` FastAPI server that **routes/stores only encrypted payloads** (does not decrypt).
- `flutter_app/` Flutter client with end-to-end encryption for text messages and encrypted file upload.

## Run backend (Docker)
```bash
docker compose up --build
```
Backend will be on http://localhost:8000

## Run Flutter app
Install Flutter SDK, then:
```bash
cd flutter_app
flutter pub get
flutter run
```

## Notes about encryption
Client uses:
- X25519 for shared secret (per-peer)
- HKDF to derive per-chat key material
- ChaCha20-Poly1305 for authenticated encryption (AEAD)

You can swap the AEAD and KDF layer with ГОСТ (via platform channels / native crypto provider) later; backend is agnostic.
