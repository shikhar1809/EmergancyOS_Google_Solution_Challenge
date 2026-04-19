void getNearbyPlacesJsonImpl(
  double lat,
  double lng,
  String type,
  Function(String) callback,
) {
  // Places API disabled - return empty results
  callback('[]');
}
