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
 * ---- Fees, and the half of them this cannot see ---------------------------
 *
 * `fees` counts what patients paid *through the app* — a consultation booked
 * against one of the practice's services and settled in the payment sheet. It
 * is not the practice's takings. Every clinic here also takes cash at the
 * desk, and nothing in the app has ever recorded a rupee of it, so a month
 * where the whole queue paid at the window reads as zero collected and is
 * correct about the only thing it can see.
 *
 * `countedOf` is how the screen can say so honestly: it is how many of the
 * window's consultations had a fee in the app at all. Where that is a
 * fraction of the consultations, the figure beside it is a fraction of the
 * money, and the screen should not be able to pretend otherwise.
 *
 * ---- What is not here, and why ---------------------------------------------
 *
 * Referrals. Nothing records one to or from another doctor, so there is no
 * field to count — absent from this response rather than present and zero, so
 * the screen can say it is not recorded instead of reporting that nobody was
 * referred.
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

/**
 * What was paid through the app in the window, and what is still owed.
 *
 * Counted off the appointment and not off any ledger, because the appointment
 * is where the amount was copied to at booking — see the note on
 * `fee.amountPaise` in models/Appointment.js. `paidPaise` is what arrived;
 * `amountPaise` is what was asked for. They are the same figure today and
 * will not be the day a partial refund exists, which is why the collected
 * total adds up the first and the outstanding total the second.
 *
 * Every appointment in the window with a fee on it counts, whatever its
 * status: a patient who paid online and then did not come has still paid, and
 * a month that quietly dropped their money would not reconcile.
 */
async function feesFor({ doctorId, practiceId, clinicId, from, to }) {
  const { start, end } = bounds(from, to);
  const rows = await Appointment.aggregate([
    {
      $match: {
        ...scope({ doctorId, practiceId, clinicId }),
        scheduledFor: { $gte: start, $lte: end },
        'fee.amountPaise': { $gt: 0 },
      },
    },
    {
      $group: {
        _id: '$fee.status',
        count: { $sum: 1 },
        asked: { $sum: '$fee.amountPaise' },
        paid: { $sum: { $ifNull: ['$fee.paidPaise', 0] } },
      },
    },
  ]);

  const by = new Map(rows.map((r) => [r._id, r]));
  const paid = by.get('paid');
  const pending = by.get('pending');
  const refunded = by.get('refunded');

  return {
    collectedPaise: paid?.paid ?? 0,
    paidCount: paid?.count ?? 0,
    outstandingPaise: pending?.asked ?? 0,
    outstandingCount: pending?.count ?? 0,
    refundedPaise: refunded?.paid ?? 0,
    // How many of the window's visits had a fee in the app at all. The screen
    // needs this to say what fraction of the money it is looking at.
    countedOf: rows.reduce((sum, r) => sum + r.count, 0),
  };
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

  const [
    now,
    before,
    average,
    fees,
    feesBefore,
    perDayRows,
    byClinicRows,
    diagnosisRows,
  ] = await Promise.all([
    countsFor({ doctorId, practiceId, clinicId, from, to }),
    countsFor({ doctorId, practiceId, clinicId, from: previous.from, to: previous.to }),
    averageConsultMinutes({ doctorId, practiceId, clinicId, from, to }),
    feesFor({ doctorId, practiceId, clinicId, from, to }),
    feesFor({ doctorId, practiceId, clinicId, from: previous.from, to: previous.to }),
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
    // What the app collected, which is not what the practice took. See the
    // note at the top of this file.
    fees: {
      collectedPaise: fees.collectedPaise,
      previousCollectedPaise: feesBefore.collectedPaise,
      outstandingPaise: fees.outstandingPaise,
      outstandingCount: fees.outstandingCount,
      refundedPaise: fees.refundedPaise,
      paidCount: fees.paidCount,
      countedOf: fees.countedOf,
      consultations: now.consultations,
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
