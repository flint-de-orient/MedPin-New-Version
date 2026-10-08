import 'appointment.dart';
import 'clinic.dart';

/// One doctor's hours at one location, as `/clinics/:id/availability` says.
///
/// A doctor either keeps the location's own hours ([usesLocationHours]) or has
/// a diary of their own there. A diary with no sittings means the doctor is not
/// at this location at all — which is different from keeping its hours, and the
/// screen says which.
class DoctorHours {
  const DoctorHours({
    required this.doctorId,
    required this.doctorName,
    this.specialty,
    required this.usesLocationHours,
    this.slotMinutes,
    this.patientsPerSlot = 1,
    this.walkInPlaces = 0,
    this.breakMinutes = 0,
    this.weeklyHours = const [],
  });

  final String doctorId;
  final String doctorName;
  final String? specialty;
  final bool usesLocationHours;

  /// The diary's slot length; null while the doctor keeps the location's.
  final int? slotMinutes;

  /// The rest of how a sitting is cut up (`Profile-Schedule`).
  ///
  /// Above one, [patientsPerSlot] is deliberate double-booking — a clinic
  /// that runs a queue rather than appointments. [walkInPlaces] are held back
  /// from the published list. [breakMinutes] is added after each patient, so
  /// a 15-minute slot with a 5-minute break starts one patient every 20.
  final int patientsPerSlot;
  final int walkInPlaces;
  final int breakMinutes;
  final List<WeeklyHour> weeklyHours;

  /// Own hours with nothing in them: not at this location.
  bool get notHere => !usesLocationHours && weeklyHours.isEmpty;

  factory DoctorHours.fromJson(Map<String, dynamic> j) {
    final doctor = j['doctor'] is Map<String, dynamic> ? j['doctor'] as Map<String, dynamic> : const {};
    final diary = j['diary'] is Map<String, dynamic> ? j['diary'] as Map<String, dynamic> : null;
    return DoctorHours(
      doctorId: doctor['id']?.toString() ?? '',
      doctorName: doctor['name']?.toString() ?? '',
      specialty: doctor['specialty']?.toString(),
      usesLocationHours: j['usesLocationHours'] != false || diary == null,
      slotMinutes: (diary?['slotMinutes'] as num?)?.toInt(),
      // The three slot rules. They were saved and never read back, so the
      // screen showed the constructor's 1 / 0 / 0 whatever the doctor had
      // set — their own setting invisible to them, which reads as a save
      // that failed. The `??` keeps an older server honest: absent is not
      // zero, it is "this server does not know", and the defaults are what
      // that server actually behaves as.
      patientsPerSlot: (diary?['patientsPerSlot'] as num?)?.toInt() ?? 1,
      walkInPlaces: (diary?['walkInPlaces'] as num?)?.toInt() ?? 0,
      breakMinutes: (diary?['breakMinutes'] as num?)?.toInt() ?? 0,
      weeklyHours:
          (diary?['weeklyHours'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(WeeklyHour.fromJson)
              .toList() ??
          const [],
    );
  }
}

/// Every doctor's hours at a location, and whether the reader may change them.
class LocationHours {
  const LocationHours({
    required this.location,
    required this.managedByYou,
    required this.doctors,
  });

  final Clinic location;
  final bool managedByYou;
  final List<DoctorHours> doctors;

  factory LocationHours.fromJson(Map<String, dynamic> j) {
    final location = j['location'] is Map<String, dynamic>
        ? j['location'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return LocationHours(
      location: Clinic.fromJson(location),
      managedByYou: location['managedByYou'] != false,
      doctors:
          (j['items'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(DoctorHours.fromJson)
              .toList() ??
          const [],
    );
  }
}

/// A sitting the same doctor already has at another location, at hours that
/// overlap the ones just saved. A warning: bookings are what may not overlap.
class HoursOverlap {
  const HoursOverlap({
    required this.locationName,
    required this.dayOfWeek,
    required this.start,
    required this.end,
  });

  final String locationName;
  final int dayOfWeek;
  final String start;
  final String end;

  factory HoursOverlap.fromJson(Map<String, dynamic> j) {
    final location = j['location'] is Map<String, dynamic> ? j['location'] as Map<String, dynamic> : const {};
    return HoursOverlap(
      locationName: location['name']?.toString() ?? '',
      dayOfWeek: (j['dayOfWeek'] as num?)?.toInt() ?? 0,
      start: j['start']?.toString() ?? '',
      end: j['end']?.toString() ?? '',
    );
  }
}

/// The appointments still standing at a location a save has just closed.
///
/// Nothing is cancelled on the patients' behalf, so the desk is shown who they
/// are, to move or call off. [total] can be more than [items] — the server
/// lists the first two hundred.
class StillBooked {
  const StillBooked({required this.total, required this.items});

  final int total;
  final List<Appointment> items;

  bool get isEmpty => total == 0;

  /// Null when the answer carries no list — the location is still open, or
  /// an older server.
  static StillBooked? fromJson(Map<String, dynamic> j) {
    final list = j['affectedAppointments'];
    if (list is! List) return null;
    final items = list.whereType<Map<String, dynamic>>().map(Appointment.fromJson).toList();
    return StillBooked(total: (j['affectedTotal'] as num?)?.toInt() ?? items.length, items: items);
  }
}
