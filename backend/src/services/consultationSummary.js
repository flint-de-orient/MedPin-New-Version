import dayjs from 'dayjs';

import { Appointment } from '../models/Appointment.js';
import { Prescription } from '../models/Prescription.js';
import { Enrollment } from '../models/Enrollment.js';
import { Clinic } from '../models/Clinic.js';

/**
 * The doctor's consultation MIS over a range of days.
 *
 * ---- Counted, never estimated ----------------------------------------------
 *
 * Every figure here is a count of rows this practice owns: appointments the
 * doctor completed, appointments nobody came to, prescriptions they issued,
 * enrolments that began. Nothing is modelled, projected or apportioned, because
 * a practice reads these numbers to decide how it is doing and a figure that
 * came from a formula cannot be checked against the diary.
 *
 * ---- What is not here, and why ---------------------------------------------
 *
 * The design also asks for fees collected and referrals. Neither exists in this
 * system: there is no money recorded against a patient anywhere — `Payment` and
 * `Invoice` are the practice's own MedPin subscription, not a consultation fee
 * — and nothing records a referral to or from another doctor. They are absent
 * from this response rather than present and zero, so the screen can say they
 * are not recorded instead of reporting that nothing was earned.
 *
 * The split by visit type is absent for the same reason: "follow-up" versus
 * "report review" is not a field, only free text in `reason`.
 *
 * ---- Average consultation time ---------------------------------------------
 *
 * Real from the day `calledAt` and `completedAt` are both written — the first
 * has always been recorded, the second only from the release that added it. An
 * appointment missing either is left out of the average rather than counted as
 * zero, and the average is null when none of them have both, which the screen
 * shows as "not recorded yet" rather than a figure.
 */

/** The statuses that mean the doctor actually saw them. */
const SEEN = ['completed'];

/** Appointments scoped to one doctor at one practice, optionally one room. */
function scope({ doctorId, practiceId, clinicId }) {
  return {
    doctor: doctorId,
    practice: practiceId,
    ...(clinicId ? { clinic: clinicId } : {}),
  };
}

/** `[start, end)` for a 'YYYY-MM-DD' range, in the server's own zone. */
function bounds(from, to) {
  return {
    start: dayjs(from).startOf('day').toDate(),
    end: dayjs(to).endOf('day').toDate(),
  };
}

/** The same number of days, immediately before — what "vs last month" means. */
function previousRange(from, to) {
  const days = dayjs(to).diff(dayjs(from), 'day') + 1;
  return {
    from: dayjs(from).subtract(days, 'day').format('YYYY-MM-DD'),
    to: dayjs(from).subtract(1, 'day').format('YYYY-MM-DD'),
  };
}

async function countsFor({ doctorId, practiceId, clinicId, from, to }) {
  const { start, end } = bounds(from, to);
  const where = scope({ doctorId, practiceId, clinicId });

  const [consultations, missed, prescriptions, newPatients] = await Promise.all([
    Appointment.countDocuments({
      ...where,
      status: { $in: SEEN },
      scheduledFor: { $gte: start, $lte: end },
    }),
    Appointment.countDocuments({
      ...where,
      status: 'no_show',
      scheduledFor: { $gte: start, $lte: end },
    }),
    Prescription.countDocuments({
      doctor: doctorId,
      practice: practiceId,
      issuedOn: { $gte: start, $lte: end },
    }),
    // Somebody this practice began looking after inside the window. Not "a
    // patient whose first appointment was here", which would count a transfer
    // twice over.
    Enrollment.countDocuments({
      practice: practiceId,
      createdAt: { $gte: start, $lte: end },
    }),
  ]);

  return { consultations, missed, prescriptions, newPatients };
}

/** Minutes between being called in and being finished, where both are known. */
async function averageConsultMinutes({ doctorId, practiceId, clinicId, from, to }) {
  const { start, end } = bounds(from, to);
  const rows = await Appointment.find({
    ...scope({ doctorId, practiceId, clinicId }),
    status: { $in: SEEN },
    scheduledFor: { $gte: start, $lte: end },
    calledAt: { $ne: null },
    completedAt: { $ne: null },
  })
    .select('calledAt completedAt')
    .lean();

  if (!rows.length) return { minutes: null, from: 0 };

  const total = rows.reduce((sum, r) => sum + (r.completedAt - r.calledAt), 0);
  return { minutes: Math.round(total / rows.length / 60000), from: rows.length };
}

export async function buildConsultationSummary({
  doctorId,
  practiceId,
  clinicId = null,
  from,
  to,
}) {
  const { start, end } = bounds(from, to);
  const where = scope({ doctorId, practiceId, clinicId });
  const seenInRange = {
    ...where,
    status: { $in: SEEN },
    scheduledFor: { $gte: start, $lte: end },
  };

  const previous = previousRange(from, to);

  const [now, before, average, perDayRows, byClinicRows, diagnosisRows] = await Promise.all([
    countsFor({ doctorId, practiceId, clinicId, from, to }),
    countsFor({ doctorId, practiceId, clinicId, from: previous.from, to: previous.to }),
    averageConsultMinutes({ doctorId, practiceId, clinicId, from, to }),
    Appointment.aggregate([
      { $match: seenInRange },
      {
        $group: {
          _id: { $dateToString: { format: '%Y-%m-%d', date: '$scheduledFor' } },
          count: { $sum: 1 },
        },
      },
      { $sort: { _id: 1 } },
    ]),
    Appointment.aggregate([
      { $match: seenInRange },
      { $group: { _id: '$clinic', count: { $sum: 1 } } },
      { $sort: { count: -1 } },
    ]),
    Prescription.aggregate([
      {
        $match: {
          doctor: doctorId,
          practice: practiceId,
          issuedOn: { $gte: start, $lte: end },
        },
      },
      { $unwind: '$diagnosis' },
      { $group: { _id: '$diagnosis', count: { $sum: 1 } } },
      { $sort: { count: -1 } },
      { $limit: 8 },
    ]),
  ]);

  // Every day in the window, including the ones with nobody in them: a clinic
  // that is shut on Sunday should show a gap, not a missing bar.
  const perDay = [];
  const counted = new Map(perDayRows.map((r) => [r._id, r.count]));
  for (let d = dayjs(from); !d.isAfter(dayjs(to), 'day'); d = d.add(1, 'day')) {
    const key = d.format('YYYY-MM-DD');
    perDay.push({ date: key, count: counted.get(key) ?? 0 });
  }

  const clinicIds = byClinicRows.map((r) => r._id).filter(Boolean);
  const clinics = clinicIds.length
    ? await Clinic.find({ _id: { $in: clinicIds } }).select('name city').lean()
    : [];
  const names = new Map(clinics.map((c) => [String(c._id), c]));

  return {
    from,
    to,
    previous,
    kpis: {
      consultations: { value: now.consultations, previous: before.consultations },
      newPatients: { value: now.newPatients, previous: before.newPatients },
      missed: { value: now.missed, previous: before.missed },
      prescriptions: { value: now.prescriptions, previous: before.prescriptions },
      // Null until something has both timestamps; `from` says how many
      // consultations the average is actually made of.
      averageMinutes: { value: average.minutes, from: average.from },
    },
    perDay,
    byLocation: byClinicRows.map((r) => ({
      clinicId: r._id ? String(r._id) : null,
      // An appointment with no room on it is still a consultation that
      // happened, and it is named as what it is rather than dropped.
      name: r._id
        ? [names.get(String(r._id))?.name, names.get(String(r._id))?.city]
            .filter(Boolean)
            .join(' · ') || 'This practice'
        : 'No location recorded',
      count: r.count,
    })),
    byDiagnosis: diagnosisRows.map((r) => ({ name: r._id, count: r.count })),
  };
}
