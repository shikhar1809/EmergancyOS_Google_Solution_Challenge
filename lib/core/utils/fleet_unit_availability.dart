import 'package:cloud_firestore/cloud_firestore.dart';

/// Heartbeat interval on the driver app is ~5s; allow a few missed ticks + latency.
/// FIX 6: Reduced from 90s to 45s — lifecycle observer handles graceful offline marking;
/// this TTL is now only the crash/OOM-kill safety net.
const Duration fleetUnitAvailabilityTtl = Duration(seconds: 45);

/// Fleet Management creates placeholder docs with ids `custom_<sanitizedCallSign>`.
/// They may carry [available]=true before any operator signs in; those rows must not
/// count as staffed for dispatch or “Standby / available” UI.
bool isFleetUnitPlaceholderDoc(String docId) => docId.startsWith('custom_');

bool _updatedAtIsFresh(Map<String, dynamic> data, [DateTime? now]) {
  final t = data['updatedAt'];
  if (t is! Timestamp) return false;
  final ref = now ?? DateTime.now();
  final diff = ref.difference(t.toDate());
  return diff <= fleetUnitAvailabilityTtl;
}

/// True when the unit is live on duty (recent [updatedAt]) and may be allotted:
/// [available] is true and the row is the live [ops_fleet_units/{firebaseUid}]
/// document, not a [custom_] slot.
bool fleetUnitIsStaffedAvailable(Map<String, dynamic> data, String docId) {
  if (data['available'] != true) return false;
  if (isFleetUnitPlaceholderDoc(docId)) return false;
  if (!_updatedAtIsFresh(data)) return false;
  return true;
}

/// Same as [fleetUnitIsStaffedAvailable] for query snapshots.
bool fleetDocIsStaffedAvailable(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
  return fleetUnitIsStaffedAvailable(doc.data(), doc.id);
}
