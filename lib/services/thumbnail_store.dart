// Picks the on-disk frame store for the target platform. The web build has no
// filesystem, so it gets a no-op store and keeps frames in memory only.
export 'thumbnail_store_io.dart' if (dart.library.js_interop) 'thumbnail_store_web.dart';
