import '../../auth/domain/user.dart';

/// What is still blank on the doctor's profile, and what each blank costs.
///
/// ---- Why there is no percentage -------------------------------------------
///
/// The artboard says "Profile 85% complete". A percentage needs an agreed
/// whole, and there is none: the app has no list of everything a profile could
/// hold, and the figure would move every time a field was added — a doctor who
/// changed nothing would watch their profile get less complete. What the app
/// does know is which of these few fields are empty, so that is what is said.
///
/// ---- And why each one names a consequence ---------------------------------
///
/// "Add your languages and a clinic photo to appear higher in patient search"
/// is the artboard's reason, and nothing here ranks anybody in a search. A
/// prompt that promises something the app does not do is how the next prompt
/// stops being believed, so each line says the thing that is actually true of
/// that gap.
class ProfileGap {
  const ProfileGap({required this.label, required this.cost, required this.route});

  final String label;

  /// What is worse while this is blank.
  final String cost;

  /// Where it is filled in.
  final String route;
}

/// The blanks, in the order they matter to a patient.
List<ProfileGap> whatIsMissing(AppUser? user, {required int rooms}) {
  final gaps = <ProfileGap>[];
  if (user == null) return gaps;

  if ((user.qualifications ?? '').trim().isEmpty) {
    gaps.add(
      const ProfileGap(
        label: 'Qualifications',
        cost: 'Your prescriptions print with no qualifications under your name.',
        route: '/clinician/more/professional',
      ),
    );
  }
  if ((user.registrationNo ?? '').trim().isEmpty) {
    gaps.add(
      const ProfileGap(
        label: 'Registration number',
        cost: 'A prescription without it can be questioned at the counter.',
        route: '/clinician/more/professional',
      ),
    );
  }
  if ((user.signatureUrl ?? '').trim().isEmpty) {
    gaps.add(
      const ProfileGap(
        label: 'Digital signature',
        cost: 'Every prescription goes out unsigned until this is uploaded.',
        route: '/clinician/more/signature',
      ),
    );
  }
  if (rooms == 0) {
    gaps.add(
      const ProfileGap(
        label: 'A location',
        cost: 'With no open location there are no hours to publish, so nobody '
            'can book a time.',
        route: '/clinician/more/locations',
      ),
    );
  }
  return gaps;
}
