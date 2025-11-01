# Storage Implementation

## Local Storage with path_provider

The app uses Flutter's `path_provider` package to access platform-specific local storage:

- **Android**: Uses `getApplicationDocumentsDirectory()` which points to the app's private storage
- **iOS**: Uses `getApplicationDocumentsDirectory()` which points to the app's Documents directory
- **Desktop**: Uses `getApplicationDocumentsDirectory()` which points to a platform-appropriate location

### Storage Location

All platforms store world data in:
- `<app_documents_dir>/worlds/test_world.json`

This is private to the app and persists across app restarts but is deleted when the app is uninstalled.

### Benefits

1. **Simple API**: Standard file I/O operations work reliably
2. **Cross-platform**: Same code works on Android, iOS, and desktop
3. **No permissions needed**: App-private storage doesn't require runtime permissions
4. **Reliable**: No URI concatenation issues like with SAF

### Code Locations

- File operations: `lib/core/storage/storage.dart` - `saveToFile()` and `loadFromFile()`
- Storage initialization: `lib/main.dart` - `_loadWorld()` and `_saveWorld()`
