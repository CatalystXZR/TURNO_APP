/**
 *
 * Project: Turno
 *
 * Original Concept: Agustin Puelma, Cristobal Cordova, Carlos Ibarra
 *
 * Software Architecture & Code: Matias Toledo (catalystxzr)
 *
 * Description: Production-grade implementation for UDD carpooling system.
 *
 * Copyright (c) 2026. All rights reserved.
 *
 */

/// App-wide constants for Turno MVP.
class AppConstants {
  AppConstants._();

  // Pricing
  static const int seatPriceCLP = 2000;
  static const int seatPricePremiumCLP = 2500;
  static const int platformFeeFixedCLP = 190;
  static const int minWithdrawalCLP = 20000;
  static const int minTopupCLP = 2000;
  static const int maxTopupCLP = 200000;
  static const double topupFeePct = 0.01;
  static const List<int> quickTopupAmountsCLP = [
    2000,
    4000,
    6000,
    10000,
    20000,
  ];

  // Legal and operations
  static const String termsVersion = 'v2.0-legal-full';
  static const String privacyPolicyVersion = 'v1.0';
  static const String privacyPolicyLastUpdated = '2026-04-19';
  static const String supportEmail = 'turnoappchile@gmail.com';
  static const String supportResponseWindow = '24-48 horas habiles';
  static const int waitTimeMinutesNoShow = 10;
  static const int lateCancellationHours = 2;
  static const int strikeBanMonths = 2;
  static const String emergencyPhoneCL = '133';

  // Allowed communes
  static const List<String> allowedCommunes = [
    'Chicureo',
    'Lo Barnechea',
    'Providencia',
    'Vitacura',
    'La Reina',
    'Buin',
  ];

  // Universidades
  static const List<Map<String, String>> universities = [
    {'code': 'UDD', 'name': 'Universidad del Desarrollo'},
    {'code': 'UANDES', 'name': 'Universidad de los Andes'},
    {'code': 'PUC', 'name': 'Pontificia Universidad Catolica de Chile'},
    {'code': 'UCH', 'name': 'Universidad de Chile'},
    {'code': 'UAI', 'name': 'Universidad Adolfo Ibanez'},
    {'code': 'UNAB', 'name': 'Universidad Andres Bello'},
  ];

  static const Set<String> premiumUniversityCodes = <String>{};

  static bool isPremiumUniversityCode(String? code) {
    return false;
  }

  static int seatPriceForUniversityCode(String? code) {
    return seatPriceCLP;
  }

  static int platformFeeForAmount(int amount, {required bool isRadial}) {
    return platformFeeFixedCLP;
  }

  static int driverNetForAmount(int amount, {required bool isRadial}) {
    return amount - platformFeeForAmount(amount, isRadial: isRadial);
  }

  static int topupFeeForAmount(int requestedAmount) {
    return (requestedAmount * topupFeePct).round();
  }

  static int topupChargedAmount(int requestedAmount) {
    return requestedAmount + topupFeeForAmount(requestedAmount);
  }


  static const List<Map<String, String>> universitiesWithIds = [
    {
      'id': '11111111-0000-0000-0000-000000000001',
      'code': 'UDD',
      'name': 'Universidad del Desarrollo',
    },
    {
      'id': '11111111-0000-0000-0000-000000000002',
      'code': 'UANDES',
      'name': 'Universidad de los Andes',
    },
    {
      'id': '11111111-0000-0000-0000-000000000003',
      'code': 'PUC',
      'name': 'Pontificia Universidad Catolica de Chile',
    },
    {
      'id': '11111111-0000-0000-0000-000000000004',
      'code': 'UCH',
      'name': 'Universidad de Chile',
    },
    {
      'id': '11111111-0000-0000-0000-000000000005',
      'code': 'UNAB',
      'name': 'Universidad Andres Bello',
    },
    {
      'id': '11111111-0000-0000-0000-000000000006',
      'code': 'UAI',
      'name': 'Universidad Adolfo Ibanez',
    },
  ];

  static const List<Map<String, String>> campusesWithIds = [
    // UDD
    {
      'id': '22222222-0001-0000-0000-000000000001',
      'university_id': '11111111-0000-0000-0000-000000000001',
      'university_name': 'Universidad del Desarrollo',
      'name': 'Campus Rector Ernesto Silva Bafalluy',
      'commune': 'Santiago',
    },
    {
      'id': '22222222-0001-0000-0000-000000000002',
      'university_id': '11111111-0000-0000-0000-000000000001',
      'university_name': 'Universidad del Desarrollo',
      'name': 'Clinica Universidad del Desarrollo',
      'commune': 'Santiago',
    },
    // UANDES
    {
      'id': '22222222-0002-0000-0000-000000000001',
      'university_id': '11111111-0000-0000-0000-000000000002',
      'university_name': 'Universidad de los Andes',
      'name': 'Campus Universitario UANDES',
      'commune': 'Las Condes',
    },
    // PUC
    {
      'id': '22222222-0003-0000-0000-000000000001',
      'university_id': '11111111-0000-0000-0000-000000000003',
      'university_name': 'Pontificia Universidad Catolica de Chile',
      'name': 'Casa Central PUC',
      'commune': 'Santiago',
    },
    {
      'id': '22222222-0003-0000-0000-000000000002',
      'university_id': '11111111-0000-0000-0000-000000000003',
      'university_name': 'Pontificia Universidad Catolica de Chile',
      'name': 'Campus San Joaquin',
      'commune': 'San Joaquin',
    },
    {
      'id': '22222222-0003-0000-0000-000000000003',
      'university_id': '11111111-0000-0000-0000-000000000003',
      'university_name': 'Pontificia Universidad Catolica de Chile',
      'name': 'Campus Oriente',
      'commune': 'Macul',
    },
    {
      'id': '22222222-0003-0000-0000-000000000004',
      'university_id': '11111111-0000-0000-0000-000000000003',
      'university_name': 'Pontificia Universidad Catolica de Chile',
      'name': 'Campus Lo Contador',
      'commune': 'Providencia',
    },
    // UCH
    {
      'id': '22222222-0004-0000-0000-000000000001',
      'university_id': '11111111-0000-0000-0000-000000000004',
      'university_name': 'Universidad de Chile',
      'name': 'Campus Andres Bello',
      'commune': 'Santiago',
    },
    {
      'id': '22222222-0004-0000-0000-000000000002',
      'university_id': '11111111-0000-0000-0000-000000000004',
      'university_name': 'Universidad de Chile',
      'name': 'Campus Beauchef',
      'commune': 'Santiago',
    },
    {
      'id': '22222222-0004-0000-0000-000000000003',
      'university_id': '11111111-0000-0000-0000-000000000004',
      'university_name': 'Universidad de Chile',
      'name': 'Campus Juan Gomez Millas',
      'commune': 'Nunoa',
    },
    {
      'id': '22222222-0004-0000-0000-000000000004',
      'university_id': '11111111-0000-0000-0000-000000000004',
      'university_name': 'Universidad de Chile',
      'name': 'Campus Dra. Eloisa Diaz',
      'commune': 'Independencia',
    },
    {
      'id': '22222222-0004-0000-0000-000000000005',
      'university_id': '11111111-0000-0000-0000-000000000004',
      'university_name': 'Universidad de Chile',
      'name': 'Campus Sur (Antumapu)',
      'commune': 'La Pintana',
    },
    // UAI
    {
      'id': '22222222-0005-0000-0000-000000000001',
      'university_id': '11111111-0000-0000-0000-000000000006',
      'university_name': 'Universidad Adolfo Ibanez',
      'name': 'Campus Penalolen',
      'commune': 'Penalolen',
    },
    {
      'id': '22222222-0005-0000-0000-000000000002',
      'university_id': '11111111-0000-0000-0000-000000000006',
      'university_name': 'Universidad Adolfo Ibanez',
      'name': 'Sede Presidente Errazuriz',
      'commune': 'Santiago',
    },
    // UNAB
    {
      'id': '22222222-0006-0000-0000-000000000001',
      'university_id': '11111111-0000-0000-0000-000000000005',
      'university_name': 'Universidad Andres Bello',
      'name': 'Campus Republica',
      'commune': 'Santiago',
    },
    {
      'id': '22222222-0006-0000-0000-000000000002',
      'university_id': '11111111-0000-0000-0000-000000000005',
      'university_name': 'Universidad Andres Bello',
      'name': 'Campus Casona de Las Condes',
      'commune': 'Las Condes',
    },
    {
      'id': '22222222-0006-0000-0000-000000000003',
      'university_id': '11111111-0000-0000-0000-000000000005',
      'university_name': 'Universidad Andres Bello',
      'name': 'Campus Bellavista',
      'commune': 'Providencia',
    },
    {
      'id': '22222222-0006-0000-0000-000000000004',
      'university_id': '11111111-0000-0000-0000-000000000005',
      'university_name': 'Universidad Andres Bello',
      'name': 'Campus Los Leones',
      'commune': 'Providencia',
    },
    {
      'id': '22222222-0006-0000-0000-000000000005',
      'university_id': '11111111-0000-0000-0000-000000000005',
      'university_name': 'Universidad Andres Bello',
      'name': 'Campus Antonio Varas',
      'commune': 'Providencia',
    },
    {
      'id': '22222222-0006-0000-0000-000000000006',
      'university_id': '11111111-0000-0000-0000-000000000005',
      'university_name': 'Universidad Andres Bello',
      'name': 'Campus Creativo',
      'commune': 'Santiago',
    },
  ];

  // Platform fee legacy fallback (not used by RPCs)
  static const int platformFeeCLP = 0;
}
