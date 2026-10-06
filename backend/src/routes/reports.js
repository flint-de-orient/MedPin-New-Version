import { Router } from 'express';
import { z } from 'zod';

import { requireAuth, requireDoctor } from '../middleware/auth.js';
import { requirePermission } from '../middleware/authorise.js';
import { practiceOf, noPractice } from '../middleware/practiceScope.js';
import { validate, q } from '../middleware/validate.js';
import { asyncHandler, badRequest } from '../middleware/errors.js';
import { PERMISSIONS } from '../models/Membership.js';
import { AuditLog } from '../models/AuditLog.js';
import { DATE_RE } from '../utils/clinicTime.js';
import { buildDailyReport, clinicToday } from '../services/dailyReport.js';
import { buildConsultationSummary } from '../services/consultationSummary.js';
import { Appointment } from '../models/Appointment.js';
import { Prescription } from '../models/Prescription.js';
import { buildDailyReportPdf } from '../services/dailyReportPdf.js';

/**
 * Reports a doctor takes out of the app.
 *
 * Mounted at /doctor/reports, before the /doctor router, as the panels are — so
 * a report request is not first walked through the doctor router's own guards
 * on its way here.
 *
 * ---- Who may ask ------------------------------------------------------------
 *
 * A doctor, for their own day, at the practice the request is for. VIEW_PATIENT
 * because the report names patients and says what was wrong with them; the
 * doctor role because the day being summarised is a doctor's consultations. A
 * member of staff with no practice is refused by the role guard, one who works
 * at two must say which, and one whose practice is suspended is refused there
 * too — this router adds nothing to those rules and removes nothing from them.
 *
 * ---- Nothing is sent from here ----------------------------------------------
 *
 * The server builds the document and hands it to the doctor's phone. Where it
 * goes after that is the doctor's choice, made in the share sheet: WhatsApp is
 * one of the places a phone can send a file, and it is never a place this
 * server sends anything.
 */
const router = Router();
router.use(requireAuth, requireDoctor, requirePermission(PERMISSIONS.VIEW_PATIENT));

/**
 * What the doctor did with it, as the audit trail records it.
 *
 *   preview   the app showed it on screen (format=json)
 *   view      the PDF was opened on the phone
 *   download  the PDF was saved
 *   share     the PDF was handed to the share sheet
 *
 * Said by the app, which is the only side that knows. The server cannot see a
 * share sheet; what it can do is refuse to hand the file over without writing
 * down what it was asked for.
 */
const PURPOSES = ['view', 'download', 'share'];

router.get(
  '/daily',
  validate({
    query: z.object({
      date: z.string().regex(DATE_RE, 'Use YYYY-MM-DD').optional(),
      format: z.enum(['pdf', 'json']).default('pdf'),
      purpose: z.enum(PURPOSES).default('download'),
    }),
  }),
  asyncHandler(async (req, res) => {
    const { format, purpose } = q(req);
    const today = clinicToday();
    const date = q(req).date ?? today;

    // A day that has not happened has nobody in it, and a report saying so
    // would read as a day with no patients. String order is date order here.
    if (date > today) throw badRequest('That date has not happened yet.');

    // Asked of the membership, never assumed. The role guard above has already
    // refused anybody with no practice on a platform that has practices; this
    // is the one left over — a platform with no memberships at all — and a
    // report scoped to no practice is not one to build.
    const practiceId = await practiceOf(req);
    if (!practiceId) throw noPractice();

    const { report, subjects } = await buildDailyReport({
      doctor: req.user,
      practiceId,
      date,
    });

    /*
     * Written before the document leaves, and awaited.
     *
     * Every other read in the app logs after the response and never fails the
     * request over it. This one hands identifiable patient data to a phone that
     * can forward it anywhere, so the order is the other way round: an export
     * that could not be recorded is not handed over.
     *
     * One row per patient named, so "who took my record out of the app" is
     * answerable from the patient's own trail; one row with no patient for a
     * day with nobody in it, so the attempt is still there.
     */
    const action = format === 'json' ? 'read' : purpose === 'share' ? 'share' : 'export';
    const meta = {
      report: 'daily',
      date,
      format,
      purpose: format === 'json' ? 'preview' : purpose,
      practice: String(practiceId),
      patients: subjects.length,
      method: req.method,
      path: '/doctor/reports/daily',
    };
    const base = {
      actor: req.user._id,
      actorRole: req.user.role,
      action,
      resource: 'DailyReport',
      ip: req.ip,
      userAgent: req.get('user-agent')?.slice(0, 300),
      meta,
      at: new Date(),
    };
    await AuditLog.insertMany(
      subjects.length ? subjects.map((patient) => ({ ...base, subjectPatient: patient })) : [base],
    );

    if (format === 'json') {
      res.setHeader('Cache-Control', 'no-store');
      return res.json({ report });
    }

    const pdf = await buildDailyReportPdf(report);
    res.type('application/pdf');
    // A date and nothing else in the name: the file name is the first thing a
    // share sheet shows the next person, and a patient's name does not belong
    // in it.
    res.setHeader(
      'Content-Disposition',
      `${purpose === 'view' ? 'inline' : 'attachment'}; filename="daily-summary-${date}.pdf"`,
    );
    res.setHeader('Cache-Control', 'no-store');
    res.send(pdf);
  }),
);

/**
 * The consultation MIS over a range of days.
 *
 * Read-only and counted from this doctor's own rows at one practice. The window
 * is theirs to choose; the comparison window is always the same number of days
 * immediately before it, because "+12% vs August" has to mean something exact.
 */
router.get(
  '/summary',
  validate({
    query: z.object({
      from: z.string().regex(DATE_RE, 'Use YYYY-MM-DD'),
      to: z.string().regex(DATE_RE, 'Use YYYY-MM-DD'),
      clinicId: z.string().optional(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const { from, to, clinicId } = q(req);
    if (from > to) throw badRequest('The range starts after it ends.');
    if (to > clinicToday()) throw badRequest('That range has not finished yet.');

    const practiceId = await practiceOf(req);
    if (!practiceId) throw noPractice();

    res.json(
      await buildConsultationSummary({
        doctorId: req.user._id,
        practiceId,
        clinicId: clinicId ?? null,
        from,
        to,
      }),
    );
  }),
);

/**
 * The consultation register: every visit in the window, newest first.
 *
 * The figures on the summary are counts of exactly these rows, so a doctor who
 * does not believe a number can read what it was counted from.
 */
router.get(
  '/consultations',
  validate({
    query: z.object({
      from: z.string().regex(DATE_RE, 'Use YYYY-MM-DD'),
      to: z.string().regex(DATE_RE, 'Use YYYY-MM-DD'),
      clinicId: z.string().optional(),
      limit: z.coerce.number().int().min(1).max(200).default(100),
    }),
  }),
  asyncHandler(async (req, res) => {
    const { from, to, clinicId, limit } = q(req);
    const practiceId = await practiceOf(req);
    if (!practiceId) throw noPractice();

    const rows = await Appointment.find({
      doctor: req.user._id,
      practice: practiceId,
      ...(clinicId ? { clinic: clinicId } : {}),
      status: 'completed',
      scheduledFor: {
        $gte: new Date(`${from}T00:00:00.000Z`),
        $lte: new Date(`${to}T23:59:59.999Z`),
      },
    })
      .select('patient scheduledFor reason clinic calledAt completedAt queueNumber')
      .sort({ scheduledFor: -1 })
      .limit(limit)
      .populate('patient', 'name')
      .populate('clinic', 'name')
      .lean();

    res.json({
      items: rows.map((a) => ({
        id: String(a._id),
        patientId: a.patient?._id ? String(a.patient._id) : null,
        patientName: a.patient?.name ?? 'Patient',
        at: a.scheduledFor,
        reason: a.reason ?? null,
        clinicName: a.clinic?.name ?? null,
        minutes:
          a.calledAt && a.completedAt
            ? Math.round((a.completedAt - a.calledAt) / 60000)
            : null,
      })),
    });
  }),
);

/**
 * The fees register: every visit the app charged for, and whether it is paid.
 *
 * ---- Not the practice's takings ------------------------------------------
 *
 * Only visits booked against one of the practice's services. The cash the desk
 * took is not in this app and never has been, so this register is a list of
 * what went through the payment sheet — which is exactly what somebody
 * reconciling a Razorpay statement needs, and exactly not what somebody
 * totting up the month's income does.
 *
 * Every status is here, not just the paid ones. "Who still owes" is the
 * question this list is most often opened for.
 */
router.get(
  '/fees',
  validate({
    query: z.object({
      from: z.string().regex(DATE_RE, 'Use YYYY-MM-DD'),
      to: z.string().regex(DATE_RE, 'Use YYYY-MM-DD'),
      clinicId: z.string().optional(),
      limit: z.coerce.number().int().min(1).max(200).default(100),
    }),
  }),
  asyncHandler(async (req, res) => {
    const { from, to, clinicId, limit } = q(req);
    const practiceId = await practiceOf(req);
    if (!practiceId) throw noPractice();

    const rows = await Appointment.find({
      doctor: req.user._id,
      practice: practiceId,
      ...(clinicId ? { clinic: clinicId } : {}),
      'fee.amountPaise': { $gt: 0 },
      scheduledFor: {
        $gte: new Date(`${from}T00:00:00.000Z`),
        $lte: new Date(`${to}T23:59:59.999Z`),
      },
    })
      .select('patient scheduledFor clinic service fee status')
      .sort({ scheduledFor: -1 })
      .limit(limit)
      .populate('patient', 'name')
      .populate('clinic', 'name')
      .populate('service', 'name')
      .lean();

    res.json({
      items: rows.map((a) => ({
        id: String(a._id),
        patientId: a.patient?._id ? String(a.patient._id) : null,
        patientName: a.patient?.name ?? 'Patient',
        at: a.scheduledFor,
        clinicName: a.clinic?.name ?? null,
        // The row that says what the amount was for. Null where the service
        // has since been removed, which withdrawal exists to prevent.
        serviceName: a.service?.name ?? null,
        amountPaise: a.fee?.amountPaise ?? 0,
        // What arrived, which is not assumed to equal what was asked.
        paidPaise: a.fee?.paidPaise ?? null,
        feeStatus: a.fee?.status ?? 'not_required',
        paidAt: a.fee?.paidAt ?? null,
        // What became of the visit itself. Somebody who paid and did not come
        // has still paid, and a register that hid that would not reconcile.
        visitStatus: a.status,
      })),
    });
  }),
);

/** The prescription register: what was prescribed in the window. */
router.get(
  '/prescriptions',
  validate({
    query: z.object({
      from: z.string().regex(DATE_RE, 'Use YYYY-MM-DD'),
      to: z.string().regex(DATE_RE, 'Use YYYY-MM-DD'),
      limit: z.coerce.number().int().min(1).max(200).default(100),
    }),
  }),
  asyncHandler(async (req, res) => {
    const { from, to, limit } = q(req);
    const practiceId = await practiceOf(req);
    if (!practiceId) throw noPractice();

    const rows = await Prescription.find({
      doctor: req.user._id,
      practice: practiceId,
      issuedOn: {
        $gte: new Date(`${from}T00:00:00.000Z`),
        $lte: new Date(`${to}T23:59:59.999Z`),
      },
    })
      .select('patient issuedOn diagnosis items labTestsAdvised followUpOn recordState')
      .sort({ issuedOn: -1 })
      .limit(limit)
      .populate('patient', 'name')
      .lean();

    res.json({
      items: rows.map((p) => ({
        id: String(p._id),
        patientId: p.patient?._id ? String(p.patient._id) : null,
        patientName: p.patient?.name ?? 'Patient',
        at: p.issuedOn,
        diagnosis: p.diagnosis ?? [],
        medicines: (p.items ?? []).length,
        tests: (p.labTestsAdvised ?? []).length,
        followUpOn: p.followUpOn ?? null,
        // A voided or replaced prescription is still part of the register; it
        // simply does not stand any more, and the register says so.
        recordState: p.recordState ?? 'current',
      })),
    });
  }),
);

/**
 * Follow-up compliance: who was asked back in the window, and whether they came.
 *
 * "Came back" means a completed appointment at this practice on or after the
 * date they were asked for. Nothing here infers intent — somebody who has not
 * come back but whose date is still ahead of them is waiting, not missing.
 */
router.get(
  '/follow-ups',
  validate({
    query: z.object({
      from: z.string().regex(DATE_RE, 'Use YYYY-MM-DD'),
      to: z.string().regex(DATE_RE, 'Use YYYY-MM-DD'),
    }),
  }),
  asyncHandler(async (req, res) => {
    const { from, to } = q(req);
    const practiceId = await practiceOf(req);
    if (!practiceId) throw noPractice();

    const asked = await Prescription.find({
      doctor: req.user._id,
      practice: practiceId,
      followUpOn: {
        $gte: new Date(`${from}T00:00:00.000Z`),
        $lte: new Date(`${to}T23:59:59.999Z`),
      },
    })
      .select('patient followUpOn')
      .sort({ followUpOn: 1 })
      .populate('patient', 'name')
      .lean();

    const today = new Date();
    const items = [];
    for (const row of asked) {
      const came = await Appointment.countDocuments({
        practice: practiceId,
        patient: row.patient?._id ?? row.patient,
        status: 'completed',
        scheduledFor: { $gte: row.followUpOn },
      });
      items.push({
        patientId: row.patient?._id ? String(row.patient._id) : null,
        patientName: row.patient?.name ?? 'Patient',
        dueOn: row.followUpOn,
        came: came > 0,
        // Still ahead of them: not a miss.
        pending: came === 0 && row.followUpOn > today,
      });
    }

    const due = items.filter((i) => !i.pending);
    res.json({
      items,
      kept: due.filter((i) => i.came).length,
      due: due.length,
    });
  }),
);

export default router;
