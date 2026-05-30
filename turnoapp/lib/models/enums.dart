/**
 *
 * Project: Turno
 *
 * Original Concept: Agustín Puelma, Cristobal Cordova, Carlos Ibarra
 *
 * Software Architecture & Code: Matías Toledo (catalystxzr)
 *
 * Description: Production-grade implementation for UDD carpooling system.
 *
 * Copyright (c) 2026. All rights reserved.
 *
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
