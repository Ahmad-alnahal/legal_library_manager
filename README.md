# MARJIY

Windows-only, Arabic-first Flutter desktop application for safely importing,
classifying, and copying legal documents into a managed local library.

The product is named **MARJIY** ("مرجعي"). The Dart package/module name remains
`legal_library_manager` for source-compatibility.

## Permanent Safety Rule

Original source files are read-only from the application's perspective. The
application must never move, rename, delete, overwrite, or modify them.

## Current Scope

The first MVP focuses on:

- Local PDF scanning and import references.
- SHA-256 hashing and exact duplicate detection.
- Manual legal metadata and classification.
- Safe opening of registered files.
- Verified copying into an application-managed library.
- Local database backups and recovery.

AI search, OCR, cloud upload, authentication, and public publishing are outside
the MVP.

## Local Development

Requirements:

- Flutter stable with bundled Dart.
- Visual Studio Build Tools with Desktop development with C++.
- Windows desktop support enabled.

Commands:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
flutter build windows
```

## Repository Safety

This Git repository is local-only unless the user explicitly changes that
decision. Do not add a remote, push, or create a pull request.

Runtime databases, backups, logs, exports, sample/private files, and legal
documents are excluded from Git.
