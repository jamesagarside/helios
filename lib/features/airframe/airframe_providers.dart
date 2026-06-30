import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/airframe/airframe_config.dart';
import '../../core/airframe/attitude_source.dart';
import '../../core/mavlink/mavlink_service.dart';
import '../../shared/models/vehicle_state.dart';
import '../../shared/providers/providers.dart';

/// The rate (Hz) at which we request ATTITUDE_QUATERNION while an Airframe
/// Model screen is active. ~50 Hz gives smooth tracking through fast manual
/// motion and VTOL transitions.
const int kAirframeHighRateHz = 50;

/// Owns the live [AttitudeSource] and the high-rate `ATTITUDE_QUATERNION`
/// stream lifecycle for the Airframe Model.
///
/// Responsibilities:
/// * rebuild the [AttitudeSource] whenever the underlying `MavlinkService`
///   changes (connect / reconnect),
/// * raise msg 31 to [kAirframeHighRateHz] while at least one screen is
///   active (reference-counted via [acquire]/[release]),
/// * restore the normal profile (stop msg 31) when the last screen leaves or
///   the link drops, and re-apply on reconnect.
class AirframeAttitudeController extends ChangeNotifier {
  AirframeAttitudeController(this._ref) {
    _ref.listen<LinkState>(linkStateProvider, _onLinkStateChanged);
    _rebuildSource();
  }

  final Ref _ref;

  AttitudeSource? _source;
  MavlinkService? _boundService;
  int _activeCount = 0;
  bool _highRateApplied = false;
  LinkState _lastLink = LinkState.disconnected;

  AttitudeSource? get source => _source;

  void _rebuildSource() {
    final service =
        _ref.read(connectionControllerProvider.notifier).mavlinkService;
    if (identical(_boundService, service)) return;
    _source?.dispose();
    _boundService = service;
    _source = service == null ? null : AttitudeSource(service);
    _highRateApplied = false;
    notifyListeners();
    // If screens are active and we just (re)connected, raise the rate.
    if (_activeCount > 0) _applyHighRate();
  }

  void _onLinkStateChanged(LinkState? prev, LinkState next) {
    final wasConnected = _lastLink == LinkState.connected ||
        _lastLink == LinkState.degraded;
    final nowConnected =
        next == LinkState.connected || next == LinkState.degraded;
    _lastLink = next;

    if (!nowConnected) {
      // Link dropped — the FC profile resets anyway; clear our flag so a
      // reconnect re-applies. Rebuild the source against the (possibly new)
      // service.
      _highRateApplied = false;
    }
    _rebuildSource();
    if (nowConnected && !wasConnected && _activeCount > 0) {
      _applyHighRate();
    }
  }

  /// Mark an Airframe Model screen as active. Returns once the high-rate
  /// request has been issued (if connected).
  void acquire() {
    _activeCount++;
    if (_activeCount == 1) _applyHighRate();
  }

  /// Release a previously [acquire]d screen. Restores the normal profile when
  /// the last screen leaves.
  void release() {
    if (_activeCount == 0) return;
    _activeCount--;
    if (_activeCount == 0) _restoreNormalRate();
  }

  void _applyHighRate() {
    if (_highRateApplied) return;
    final service =
        _ref.read(connectionControllerProvider.notifier).mavlinkService;
    if (service == null) return;
    final vehicle = _ref.read(vehicleStateProvider);
    if (vehicle.systemId == 0) return;
    _highRateApplied = true;
    service.setAttitudeQuaternionRate(
      targetSystem: vehicle.systemId,
      targetComponent: vehicle.componentId,
      rateHz: kAirframeHighRateHz,
    );
  }

  void _restoreNormalRate() {
    if (!_highRateApplied) return;
    _highRateApplied = false;
    final service =
        _ref.read(connectionControllerProvider.notifier).mavlinkService;
    if (service == null) return;
    final vehicle = _ref.read(vehicleStateProvider);
    if (vehicle.systemId == 0) return;
    service.stopAttitudeQuaternion(
      targetSystem: vehicle.systemId,
      targetComponent: vehicle.componentId,
    );
  }

  @override
  void dispose() {
    _restoreNormalRate();
    _source?.dispose();
    super.dispose();
  }
}

/// Provider for the Airframe Model attitude controller.
final airframeAttitudeControllerProvider =
    ChangeNotifierProvider<AirframeAttitudeController>(
  (ref) => AirframeAttitudeController(ref),
);

/// Resolves the current [AirframeConfig] from FRAME_CLASS/FRAME_TYPE params
/// (when loaded) with a MAV_TYPE fallback. Recomputes only when the inputs
/// change.
final airframeConfigProvider = Provider<AirframeConfig>((ref) {
  final vehicle = ref.watch(vehicleStateProvider);
  final params = ref.watch(paramCacheProvider);
  final frameClass = params['FRAME_CLASS']?.value.toInt();
  final frameType = params['FRAME_TYPE']?.value.toInt();
  return AirframeConfig.resolve(
    vehicleType: vehicle.vehicleType,
    frameClass: frameClass,
    frameType: frameType,
  );
});
