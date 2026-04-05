/// Web platform initialisation.
///
/// Skips native-only dependencies (MediaKit, FMTC ObjectBox).
Future<void> initialise() async {
  // No native initialisation needed on web.
  // MediaKit (video) and FMTC (tile caching) use FFI and are not available.
}
