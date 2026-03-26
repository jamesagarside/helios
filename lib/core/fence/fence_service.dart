import '../../shared/models/fence_zone.dart';
import '../../shared/models/mission_item.dart';
import '../mission/mission_service.dart';

/// Service for uploading/downloading geofence zones.
///
/// Uses the mission protocol with MavMissionType.fence (1).
/// Fence items are MISSION_ITEM_INT with fence-specific commands.
class FenceService {
  FenceService(this._missionService);

  final MissionService _missionService;

  /// Download fence zones from vehicle.
  Future<List<FenceZone>> download({
    required int targetSystem,
    required int targetComponent,
    void Function(double)? onProgress,
  }) async {
    // Use mission download with fence mission type
    // The MissionService needs to support mission type parameter.
    // For now, we build fence-specific frames manually.
    // TODO: extend MissionService to accept missionType parameter
    final items = await _missionService.download(
      targetSystem: targetSystem,
      targetComponent: targetComponent,
      onProgress: onProgress,
    );
    return FenceZone.fromMissionItems(items);
  }

  /// Upload fence zones to vehicle.
  Future<void> upload({
    required int targetSystem,
    required int targetComponent,
    required List<FenceZone> zones,
    void Function(double)? onProgress,
  }) async {
    // Convert zones to mission items
    final items = <MissionItem>[];
    var seq = 0;
    for (final zone in zones) {
      final zoneItems = zone.toMissionItems(seq);
      items.addAll(zoneItems);
      seq += zoneItems.length;
    }

    await _missionService.upload(
      targetSystem: targetSystem,
      targetComponent: targetComponent,
      items: items,
      onProgress: onProgress,
    );
  }

  /// Clear fence on vehicle.
  Future<void> clear({
    required int targetSystem,
    required int targetComponent,
  }) async {
    await _missionService.upload(
      targetSystem: targetSystem,
      targetComponent: targetComponent,
      items: [],
    );
  }
}
