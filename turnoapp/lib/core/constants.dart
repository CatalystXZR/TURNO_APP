/**
 * Project: Turno
 * 
 * Project Owners: Cristobal Cordova, Carlos Ibarra, Agustin Puelma
 * Software Architecture & Code: Matias Toledo (@catalystxzr)
 * 
 * Description: Production-grade implementation for UDD carpooling system.
 * 
 * Copyright (c) 2026 Turno. All rights reserved.
 * This software is proprietary and confidential.
 */

/// App-wide constants for Turno MVP.
class AppConstants {
  AppConstants._();

  // Pricing
  static const int seatPriceCLP = 2000;

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
      'name': 'Rector Ernesto Silva Bafalluy',
      'commune': 'Las Condes',
    },
    {
      'id': '22222222-0001-0000-0000-000000000002',
      'university_id': '11111111-0000-0000-0000-000000000001',
      'university_name': 'Universidad del Desarrollo',
      'name': 'Las Condes',
      'commune': 'Las Condes',
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
      'name': 'Casa Central',
      'commune': 'Santiago',
    },
    {
      'id': '22222222-0003-0000-0000-000000000002',
      'university_id': '11111111-0000-0000-0000-000000000003',
      'university_name': 'Pontificia Universidad Catolica de Chile',
      'name': 'San Joaquín',
      'commune': 'Macul',
    },
    {
      'id': '22222222-0003-0000-0000-000000000003',
      'university_id': '11111111-0000-0000-0000-000000000003',
      'university_name': 'Pontificia Universidad Catolica de Chile',
      'name': 'Oriente',
      'commune': 'Providencia',
    },
    {
      'id': '22222222-0003-0000-0000-000000000004',
      'university_id': '11111111-0000-0000-0000-000000000003',
      'university_name': 'Pontificia Universidad Catolica de Chile',
      'name': 'Lo Contador',
      'commune': 'Providencia',
    },
    {
      'id': '22222222-0003-0000-0000-000000000005',
      'university_id': '11111111-0000-0000-0000-000000000003',
      'university_name': 'Pontificia Universidad Catolica de Chile',
      'name': 'Villarrica',
      'commune': 'Villarrica',
    },
    // UCH
    {
      'id': '22222222-0004-0000-0000-000000000001',
      'university_id': '11111111-0000-0000-0000-000000000004',
      'university_name': 'Universidad de Chile',
      'name': 'Andrés Bello',
      'commune': 'Providencia',
    },
    {
      'id': '22222222-0004-0000-0000-000000000002',
      'university_id': '11111111-0000-0000-0000-000000000004',
      'university_name': 'Universidad de Chile',
      'name': 'Beauchef',
      'commune': 'Santiago',
    },
    {
      'id': '22222222-0004-0000-0000-000000000003',
      'university_id': '11111111-0000-0000-0000-000000000004',
      'university_name': 'Universidad de Chile',
      'name': 'Juan Gómez Millas',
      'commune': 'Ñuñoa',
    },
    {
      'id': '22222222-0004-0000-0000-000000000004',
      'university_id': '11111111-0000-0000-0000-000000000004',
      'university_name': 'Universidad de Chile',
      'name': 'Norte',
      'commune': 'Independencia',
    },
    {
      'id': '22222222-0004-0000-0000-000000000005',
      'university_id': '11111111-0000-0000-0000-000000000004',
      'university_name': 'Universidad de Chile',
      'name': 'Sur',
      'commune': 'La Pintana',
    },
    {
      'id': '22222222-0004-0000-0000-000000000006',
      'university_id': '11111111-0000-0000-0000-000000000004',
      'university_name': 'Universidad de Chile',
      'name': 'Casa Central',
      'commune': 'Santiago',
    },
    // UAI
    {
      'id': '22222222-0005-0000-0000-000000000001',
      'university_id': '11111111-0000-0000-0000-000000000006',
      'university_name': 'Universidad Adolfo Ibanez',
      'name': 'Peñalolén',
      'commune': 'Peñalolén',
    },
    {
      'id': '22222222-0005-0000-0000-000000000002',
      'university_id': '11111111-0000-0000-0000-000000000006',
      'university_name': 'Universidad Adolfo Ibanez',
      'name': 'Presidente Errázuriz',
      'commune': 'Las Condes',
    },
    // UNAB
    {
      'id': '22222222-0006-0000-0000-000000000001',
      'university_id': '11111111-0000-0000-0000-000000000005',
      'university_name': 'Universidad Andres Bello',
      'name': 'República',
      'commune': 'Santiago',
    },
    {
      'id': '22222222-0006-0000-0000-000000000002',
      'university_id': '11111111-0000-0000-0000-000000000005',
      'university_name': 'Universidad Andres Bello',
      'name': 'Casona de Las Condes',
      'commune': 'Las Condes',
    },
    {
      'id': '22222222-0006-0000-0000-000000000003',
      'university_id': '11111111-0000-0000-0000-000000000005',
      'university_name': 'Universidad Andres Bello',
      'name': 'Bellavista',
      'commune': 'Providencia',
    },
    {
      'id': '22222222-0006-0000-0000-000000000004',
      'university_id': '11111111-0000-0000-0000-000000000005',
      'university_name': 'Universidad Andres Bello',
      'name': 'Los Leones',
      'commune': 'Providencia',
    },
    {
      'id': '22222222-0006-0000-0000-000000000005',
      'university_id': '11111111-0000-0000-0000-000000000005',
      'university_name': 'Universidad Andres Bello',
      'name': 'Antonio Varas',
      'commune': 'Providencia',
    },
    {
      'id': '22222222-0006-0000-0000-000000000006',
      'university_id': '11111111-0000-0000-0000-000000000005',
      'university_name': 'Universidad Andres Bello',
      'name': 'Creativo',
      'commune': 'Recoleta',
    },
  ];

}
