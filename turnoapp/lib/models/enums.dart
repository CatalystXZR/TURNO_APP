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

enum RoleMode { passenger, driver }

enum BookingStatus { reserved, cancelled, completed, noShow }

enum BookingDispatchStatus {
  reserved,
  accepted,
  driverArriving,
  driverArrived,
  passengerBoarded,
  inProgress,
  completed,
  cancelled,
  noShow,
}

enum RideDirection { toCampus, fromCampus }

enum TxType {
  topup,
  bookingHold,
  releaseToDriver,
  platformFee,
  refund,
  withdrawalRequest,
  withdrawalPaid,
  penalty,
}
