import 'package:geolocator/geolocator.dart';

class PharmacyPlace {
  final String name;
  final String vicinity;
  final double lat;
  final double lng;
  final String phoneNumber;
  final bool is24Hours;
  final List<String> availableMedicines;
  final String? openNow;

  PharmacyPlace({
    required this.name,
    required this.vicinity,
    required this.lat,
    required this.lng,
    this.phoneNumber = '',
    this.is24Hours = false,
    this.availableMedicines = const [],
    this.openNow,
  });

  factory PharmacyPlace.fromJson(Map<String, dynamic> j) => PharmacyPlace(
    name: j['name'] ?? '',
    vicinity: j['vicinity'] ?? '',
    lat: (j['lat'] ?? 0.0).toDouble(),
    lng: (j['lng'] ?? 0.0).toDouble(),
    phoneNumber: j['phoneNumber'] ?? '',
    is24Hours: j['is24Hours'] ?? false,
    availableMedicines: (j['availableMedicines'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    openNow: j['openNow'],
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'vicinity': vicinity,
    'lat': lat,
    'lng': lng,
    'phoneNumber': phoneNumber,
    'is24Hours': is24Hours,
    'availableMedicines': availableMedicines,
    'openNow': openNow,
  };

  double distanceKm(double userLat, double userLng) {
    return Geolocator.distanceBetween(userLat, userLng, lat, lng) / 1000;
  }

  String get medicineFilterSummary {
    if (availableMedicines.isEmpty) return 'General medicines';
    final categories = <String>{};
    for (final med in availableMedicines) {
      final m = med.toLowerCase();
      if (m.contains('ors') || m.contains('oral rehydration')) {
        categories.add('ORS');
      }
      if (m.contains('insulin') || m.contains('diabetes')) {
        categories.add('Diabetes');
      }
      if (m.contains('cardiac') || m.contains('heart') || m.contains('aspirin') || m.contains('nitro')) {
        categories.add('Cardiac');
      }
      if (m.contains('antibiotic') || m.contains('amoxicillin') || m.contains('azithromycin')) {
        categories.add('Antibiotics');
      }
      if (m.contains('pain') || m.contains('paracetamol') || m.contains('ibuprofen')) {
        categories.add('Pain Relief');
      }
    }
    return categories.isEmpty ? 'General' : categories.join(' · ');
  }
}

class CoolingCenter {
  final String name;
  final String address;
  final double lat;
  final double lng;
  final String phoneNumber;
  final String? facilities;
  final bool hasORS;
  final bool hasMedicalSupport;
  final String? operatingHours;

  CoolingCenter({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    this.phoneNumber = '',
    this.facilities,
    this.hasORS = false,
    this.hasMedicalSupport = false,
    this.operatingHours,
  });

  factory CoolingCenter.fromJson(Map<String, dynamic> j) => CoolingCenter(
    name: j['name'] ?? '',
    address: j['address'] ?? '',
    lat: (j['lat'] ?? 0.0).toDouble(),
    lng: (j['lng'] ?? 0.0).toDouble(),
    phoneNumber: j['phoneNumber'] ?? '',
    facilities: j['facilities'],
    hasORS: j['hasORS'] ?? false,
    hasMedicalSupport: j['hasMedicalSupport'] ?? false,
    operatingHours: j['operatingHours'],
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    'lat': lat,
    'lng': lng,
    'phoneNumber': phoneNumber,
    'facilities': facilities,
    'hasORS': hasORS,
    'hasMedicalSupport': hasMedicalSupport,
    'operatingHours': operatingHours,
  };

  double distanceKm(double userLat, double userLng) {
    return Geolocator.distanceBetween(userLat, userLng, lat, lng) / 1000;
  }
}

class BloodBankInfo {
  final String name;
  final String address;
  final double lat;
  final double lng;
  final String phoneNumber;
  final Map<String, String> bloodGroups;
  final bool hasApheresis;
  final String? lastUpdated;

  BloodBankInfo({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    this.phoneNumber = '',
    this.bloodGroups = const {},
    this.hasApheresis = false,
    this.lastUpdated,
  });

  factory BloodBankInfo.fromJson(Map<String, dynamic> j) => BloodBankInfo(
    name: j['name'] ?? '',
    address: j['address'] ?? '',
    lat: (j['lat'] ?? 0.0).toDouble(),
    lng: (j['lng'] ?? 0.0).toDouble(),
    phoneNumber: j['phoneNumber'] ?? '',
    bloodGroups: (j['bloodGroups'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())) ?? {},
    hasApheresis: j['hasApheresis'] ?? false,
    lastUpdated: j['lastUpdated'],
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    'lat': lat,
    'lng': lng,
    'phoneNumber': phoneNumber,
    'bloodGroups': bloodGroups,
    'hasApheresis': hasApheresis,
    'lastUpdated': lastUpdated,
  };

  double distanceKm(double userLat, double userLng) {
    return Geolocator.distanceBetween(userLat, userLng, lat, lng) / 1000;
  }

  String get bloodGroupSummary {
    if (bloodGroups.isEmpty) return 'Availability unknown';
    return bloodGroups.entries.map((e) => '${e.key}: ${e.value}').join(' | ');
  }

  bool hasCriticalBlood(String group) {
    final status = bloodGroups[group]?.toLowerCase() ?? '';
    return status.contains('available') || status.contains('yes') || status.contains('stock');
  }
}

class DiseaseOutbreak {
  final String disease;
  final String severity;
  final String affectedArea;
  final String description;
  final List<String> precautions;
  final String source;
  final DateTime reportedDate;
  final int? reportedCases;
  final String? advisoryLevel;

  DiseaseOutbreak({
    required this.disease,
    required this.severity,
    required this.affectedArea,
    required this.description,
    required this.precautions,
    required this.source,
    required this.reportedDate,
    this.reportedCases,
    this.advisoryLevel,
  });

  factory DiseaseOutbreak.fromJson(Map<String, dynamic> j) => DiseaseOutbreak(
    disease: j['disease'] ?? '',
    severity: j['severity'] ?? 'Medium',
    affectedArea: j['affectedArea'] ?? '',
    description: j['description'] ?? '',
    precautions: (j['precautions'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    source: j['source'] ?? 'Health Department',
    reportedDate: j['reportedDate'] != null ? DateTime.parse(j['reportedDate']) : DateTime.now(),
    reportedCases: j['reportedCases'],
    advisoryLevel: j['advisoryLevel'],
  );

  Map<String, dynamic> toJson() => {
    'disease': disease,
    'severity': severity,
    'affectedArea': affectedArea,
    'description': description,
    'precautions': precautions,
    'source': source,
    'reportedDate': reportedDate.toIso8601String(),
    'reportedCases': reportedCases,
    'advisoryLevel': advisoryLevel,
  };

  bool get isCritical => severity.toLowerCase() == 'critical' || severity.toLowerCase() == 'high';
}

class AQIInfo {
  final double aqi;
  final String category;
  final String healthImpact;
  final String advice;
  final String maskAdvisory;
  final bool isIndoorRecommended;
  final List<String> sensitiveGroups;
  final DateTime timestamp;

  AQIInfo({
    required this.aqi,
    required this.category,
    required this.healthImpact,
    required this.advice,
    required this.maskAdvisory,
    required this.isIndoorRecommended,
    this.sensitiveGroups = const [],
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory AQIInfo.fromAQI(double aqiValue, {String city = 'Unknown'}) {
    final info = _getAQIInfo(aqiValue);
    return AQIInfo(
      aqi: aqiValue,
      category: info['category']!,
      healthImpact: info['healthImpact']!,
      advice: info['advice']!,
      maskAdvisory: info['maskAdvisory']!,
      isIndoorRecommended: aqiValue > 100,
      sensitiveGroups: _getSensitiveGroups(aqiValue),
    );
  }

  static Map<String, String> _getAQIInfo(double aqi) {
    if (aqi <= 50) {
      return {
        'category': 'Good',
        'healthImpact': 'Air quality is satisfactory. Outdoor activities are safe.',
        'advice': 'Enjoy outdoor activities.',
        'maskAdvisory': 'No mask needed.',
      };
    } else if (aqi <= 100) {
      return {
        'category': 'Moderate',
        'healthImpact': 'Acceptable air quality. May affect unusually sensitive people.',
        'advice': 'Unusually sensitive people should consider limiting prolonged outdoor exertion.',
        'maskAdvisory': 'Sensitive groups may wear N95 mask outdoors.',
      };
    } else if (aqi <= 150) {
      return {
        'category': 'Unhealthy for Sensitive Groups',
        'healthImpact': 'Members of sensitive groups may experience health effects. General public less likely to be affected.',
        'advice': 'Sensitive groups should reduce prolonged outdoor exertion. Others limit outdoor exertion.',
        'maskAdvisory': 'N95 mask recommended for sensitive groups outdoors.',
      };
    } else if (aqi <= 200) {
      return {
        'category': 'Unhealthy',
        'healthImpact': 'Everyone may begin to experience health effects. Sensitive groups may experience more serious effects.',
        'advice': 'Everyone should reduce prolonged outdoor exertion. Sensitive groups avoid outdoor activity.',
        'maskAdvisory': 'N95 mask mandatory outdoors. Avoid going outside if possible.',
      };
    } else if (aqi <= 300) {
      return {
        'category': 'Very Unhealthy',
        'healthImpact': 'Health alert: everyone may experience more serious health effects.',
        'advice': 'Everyone should avoid outdoor exertion. Keep windows closed.',
        'maskAdvisory': 'N95 or P100 mask mandatory if going outside. Stay indoors.',
      };
    } else {
      return {
        'category': 'Hazardous',
        'healthImpact': 'Health warning of emergency conditions. Everyone is more likely to be affected.',
        'advice': 'Stay indoors. Close all windows and doors. Use air purifier if available.',
        'maskAdvisory': 'P100 mask mandatory. Avoid all outdoor activity. This is a health emergency.',
      };
    }
  }

  static List<String> _getSensitiveGroups(double aqi) {
    final groups = <String>[];
    if (aqi > 50) groups.add('Children');
    if (aqi > 75) groups.add('Elderly');
    if (aqi > 100) {
      groups.add('Asthma patients');
      groups.add('Heart disease patients');
    }
    if (aqi > 150) {
      groups.add('Pregnant women');
      groups.add('COPD patients');
    }
    return groups;
  }

  String get personalizedImpact {
    final impacts = <String>[];
    for (final group in sensitiveGroups) {
      if (group.toLowerCase().contains('asthma')) {
        impacts.add('Today\'s AQI ($aqi) is harmful for asthma patients.');
      }
      if (group.toLowerCase().contains('heart')) {
        impacts.add('Cardiac patients should avoid outdoor exposure.');
      }
      if (group.toLowerCase().contains('children')) {
        impacts.add('Keep children indoors during peak hours.');
      }
    }
    return impacts.isEmpty ? healthImpact : impacts.join(' ');
  }
}

class EmergencyServicesService {
  static List<PharmacyPlace> getNearbyPharmacies(
    double lat,
    double lng,
    double radiusKm, {
    String? medicineFilter,
    bool openNowOnly = false,
  }) {
    final cached = _loadPharmacies();
    return cached.where((p) {
      final dist = p.distanceKm(lat, lng);
      if (dist > radiusKm) return false;
      if (openNowOnly && p.openNow == 'closed') return false;
      if (medicineFilter != null && medicineFilter.isNotEmpty) {
        return p.availableMedicines.any((m) =>
          m.toLowerCase().contains(medicineFilter.toLowerCase()));
      }
      return true;
    }).toList()
      ..sort((a, b) => a.distanceKm(lat, lng).compareTo(b.distanceKm(lat, lng)));
  }

  static List<CoolingCenter> getNearbyCoolingCenters(double lat, double lng, double radiusKm) {
    final cached = _loadCoolingCenters();
    return cached.where((c) => c.distanceKm(lat, lng) <= radiusKm).toList()
      ..sort((a, b) => a.distanceKm(lat, lng).compareTo(b.distanceKm(lat, lng)));
  }

  static List<BloodBankInfo> getNearbyBloodBanks(double lat, double lng, double radiusKm) {
    final cached = _loadBloodBanks();
    return cached.where((b) => b.distanceKm(lat, lng) <= radiusKm).toList()
      ..sort((a, b) => a.distanceKm(lat, lng).compareTo(b.distanceKm(lat, lng)));
  }

  static List<DiseaseOutbreak> getActiveOutbreaks() {
    return _loadOutbreaks();
  }

  static Future<AQIInfo> getAQI(double lat, double lng) async {
    // Placeholder: returns mid-AQI sample until the real OpenWeather API
    // integration is wired up. Kept async so callers can await safely.
    try {
      return AQIInfo.fromAQI(150, city: 'Your Area');
    } catch (_) {
      return AQIInfo.fromAQI(100, city: 'Your Area');
    }
  }

  static List<PharmacyPlace> _loadPharmacies() {
    return _demoPharmacies;
  }

  static List<CoolingCenter> _loadCoolingCenters() {
    return _demoCoolingCenters;
  }

  static List<BloodBankInfo> _loadBloodBanks() {
    return _demoBloodBanks;
  }

  static List<DiseaseOutbreak> _loadOutbreaks() {
    return _demoOutbreaks;
  }

  static final List<PharmacyPlace> _demoPharmacies = [
    PharmacyPlace(
      name: 'MedPlus 24hr Pharmacy',
      vicinity: 'MG Road, Near City Hospital',
      lat: 26.8467,
      lng: 80.9462,
      phoneNumber: '1800-123-001',
      is24Hours: true,
      availableMedicines: ['ORS Sachets', 'Paracetamol', 'Insulin', 'Aspirin', 'Amoxicillin'],
    ),
    PharmacyPlace(
      name: 'Apollo Pharmacy',
      vicinity: 'Hazratganj',
      lat: 26.8500,
      lng: 80.9400,
      phoneNumber: '1800-234-002',
      is24Hours: false,
      openNow: 'Open',
      availableMedicines: ['Cardiac drugs', 'Blood pressure meds', 'Paracetamol', 'ORS'],
    ),
    PharmacyPlace(
      name: 'LifeCare Chemists',
      vicinity: 'Gomtinagar',
      lat: 26.8300,
      lng: 80.9500,
      phoneNumber: '1800-345-003',
      is24Hours: true,
      availableMedicines: ['Insulin', 'Glucose meter strips', 'ORS Sachets', 'Pain relief'],
    ),
    PharmacyPlace(
      name: 'HealthFirst Pharmacy',
      vicinity: 'Alambagh',
      lat: 26.8100,
      lng: 80.9100,
      phoneNumber: '1800-456-004',
      is24Hours: false,
      openNow: 'Open',
      availableMedicines: ['Antibiotics', 'Pain relief', 'Cold medications', 'First aid supplies'],
    ),
    PharmacyPlace(
      name: 'Emergency Medshop',
      vicinity: 'Kanpur Road',
      lat: 26.8200,
      lng: 80.9300,
      phoneNumber: '1800-567-005',
      is24Hours: true,
      availableMedicines: ['Cardiac drugs', 'Nitro tablets', 'Aspirin', 'Clopidogrel', 'Atorvastatin'],
    ),
  ];

  static final List<CoolingCenter> _demoCoolingCenters = [
    CoolingCenter(
      name: 'UP Govt Cooling Center - Indira Nagar',
      address: 'Indira Nagar Community Hall, Block A',
      lat: 26.8400,
      lng: 80.9600,
      phoneNumber: '0522-234-5678',
      facilities: 'AC Hall, Clean drinking water, Fans',
      hasORS: true,
      hasMedicalSupport: true,
      operatingHours: '8 AM - 8 PM',
    ),
    CoolingCenter(
      name: 'Mahanagar Cooling Shelter',
      address: 'Mahanagar Market Complex, Ground Floor',
      lat: 26.8550,
      lng: 80.9450,
      phoneNumber: '0522-345-6789',
      facilities: 'Air Cooler, Water dispensers, Rest area',
      hasORS: true,
      hasMedicalSupport: false,
      operatingHours: '6 AM - 10 PM',
    ),
    CoolingCenter(
      name: 'Alambagh Heat Relief Center',
      address: 'Alambagh Bus Stand Complex',
      lat: 26.8150,
      lng: 80.9150,
      phoneNumber: '0522-456-7890',
      facilities: 'Cooler Room, ORS Distribution, Medical Kit',
      hasORS: true,
      hasMedicalSupport: true,
      operatingHours: '24 Hours',
    ),
    CoolingCenter(
      name: 'Gomtinagar Community Center',
      address: 'Vikas Nagar, Sector 12',
      lat: 26.8280,
      lng: 80.9550,
      phoneNumber: '0522-567-8901',
      facilities: 'AC Room, Drinking water, First aid',
      hasORS: true,
      hasMedicalSupport: false,
      operatingHours: '7 AM - 9 PM',
    ),
    CoolingCenter(
      name: 'Hazaratganj Public Cooling Point',
      address: 'Near Lal Bahadur Shastri Statue',
      lat: 26.8520,
      lng: 80.9420,
      phoneNumber: '0522-678-9012',
      facilities: 'Shaded area, Water tank, Fans',
      hasORS: true,
      hasMedicalSupport: false,
      operatingHours: '8 AM - 6 PM',
    ),
  ];

  static final List<BloodBankInfo> _demoBloodBanks = [
    BloodBankInfo(
      name: 'Lok Bandhu Rajendra Prasad Blood Bank',
      address: 'MGM Hospital, New Bailey Road',
      lat: 26.8380,
      lng: 80.9280,
      phoneNumber: '0522-222-3456',
      bloodGroups: {
        'A+': 'Available',
        'A-': 'Limited',
        'B+': 'Available',
        'B-': 'Available',
        'AB+': 'Limited',
        'AB-': 'Out of Stock',
        'O+': 'Available',
        'O-': 'Limited',
      },
      hasApheresis: true,
      lastUpdated: DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
    ),
    BloodBankInfo(
      name: 'SGPGIMS Blood Bank',
      address: 'Sanjay Gandhi Post Graduate Institute',
      lat: 26.8480,
      lng: 80.9150,
      phoneNumber: '0522-266-8001',
      bloodGroups: {
        'A+': 'Available',
        'A-': 'Available',
        'B+': 'Available',
        'B-': 'Limited',
        'AB+': 'Available',
        'AB-': 'Available',
        'O+': 'Limited',
        'O-': 'Out of Stock',
      },
      hasApheresis: true,
      lastUpdated: DateTime.now().subtract(const Duration(hours: 4)).toIso8601String(),
    ),
    BloodBankInfo(
      name: 'Balrampur Hospital Blood Bank',
      address: 'Gola Road',
      lat: 26.8350,
      lng: 80.9350,
      phoneNumber: '0522-223-4567',
      bloodGroups: {
        'A+': 'Available',
        'A-': 'Out of Stock',
        'B+': 'Available',
        'B-': 'Available',
        'AB+': 'Limited',
        'AB-': 'Limited',
        'O+': 'Available',
        'O-': 'Out of Stock',
      },
      hasApheresis: false,
      lastUpdated: DateTime.now().subtract(const Duration(hours: 6)).toIso8601String(),
    ),
    BloodBankInfo(
      name: 'Civil Hospital Blood Bank',
      address: 'Near Charbagh Station',
      lat: 26.8300,
      lng: 80.9200,
      phoneNumber: '0522-224-5678',
      bloodGroups: {
        'A+': 'Limited',
        'A-': 'Available',
        'B+': 'Available',
        'B-': 'Limited',
        'AB+': 'Available',
        'AB-': 'Available',
        'O+': 'Limited',
        'O-': 'Available',
      },
      hasApheresis: true,
      lastUpdated: DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
    ),
  ];

  static final List<DiseaseOutbreak> _demoOutbreaks = [
    DiseaseOutbreak(
      disease: 'Dengue',
      severity: 'High',
      affectedArea: 'Lucknow District',
      description: 'Rising dengue cases reported in urban areas. Mosquito breeding grounds identified near residential colonies.',
      precautions: [
        'Use mosquito repellent containing DEET',
        'Wear full-sleeved clothing outdoors',
        'Remove standing water near your home',
        'Use mosquito nets while sleeping',
        'Take paracetamol for fever - avoid aspirin',
        'Seek medical help if fever exceeds 102°F',
      ],
      source: 'District Health Department, Lucknow',
      reportedDate: DateTime.now().subtract(const Duration(days: 2)),
      reportedCases: 127,
      advisoryLevel: 'Orange Alert',
    ),
    DiseaseOutbreak(
      disease: 'Cholera',
      severity: 'Medium',
      affectedArea: 'Peripheral areas of Lucknow',
      description: 'Suspected cholera cases in low-lying areas. Water contamination suspected.',
      precautions: [
        'Drink only boiled or bottled water',
        'Avoid street food and uncovered drinks',
        'Use ORS solution if experiencing diarrhea',
        'Wash hands frequently with soap',
        'Keep food covered at all times',
        'Report any diarrhea cases to nearest health center',
      ],
      source: 'UP State Health Department',
      reportedDate: DateTime.now().subtract(const Duration(days: 5)),
      reportedCases: 23,
      advisoryLevel: 'Yellow Advisory',
    ),
    DiseaseOutbreak(
      disease: 'Japanese Encephalitis',
      severity: 'High',
      affectedArea: 'Rural Lucknow and adjoining districts',
      description: 'JE cases reported during monsoon season. Pigs act as reservoir hosts.',
      precautions: [
        'Get Japanese Encephalitis vaccination',
        'Avoid outdoor activities during dusk/dawn',
        'Use mosquito repellent regularly',
        'Keep pigs away from residential areas',
        'Cover all windows with mosquito screens',
        'Seek immediate medical attention for high fever',
      ],
      source: 'National Vector Borne Disease Control Programme',
      reportedDate: DateTime.now().subtract(const Duration(days: 3)),
      reportedCases: 45,
      advisoryLevel: 'Orange Alert',
    ),
    DiseaseOutbreak(
      disease: 'Heatwave',
      severity: 'Critical',
      affectedArea: 'Entire Lucknow District',
      description: 'Temperature exceeding 44°C expected. Heat wave conditions persisting for 5+ days.',
      precautions: [
        'Stay indoors between 12 PM - 4 PM',
        'Drink water every 20 minutes outdoors',
        'Wear light-colored, loose cotton clothes',
        'Apply sunscreen before going outside',
        'Visit nearest cooling center if feeling unwell',
        'Check on elderly and children twice daily',
        'Do not leave children or pets in parked vehicles',
      ],
      source: 'India Meteorological Department',
      reportedDate: DateTime.now().subtract(const Duration(hours: 12)),
      advisoryLevel: 'Red Alert',
    ),
  ];
}
