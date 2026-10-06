import { Router } from 'express';
import { z } from 'zod';

import { requireAuth, requireDoctor } from '../middleware/auth.js';
import { requirePermission } from '../middleware/authorise.js';
import { practiceOf, noPractice } from '../middleware/practiceScope.js';
import { validate, q } from '../middleware/validate.js';
import { asyncHandler, notFound, conflict } from '../middleware/errors.js';
import { audit } from '../middleware/audit.js';
import { PERMISSIONS } from '../models/Membership.js';
import { Service, rupeesOf } from '../models/Service.js';
import { Appointment } from '../models/Appointment.js';

/**
 * What the practice charges for a consultation.
 *
 * Mounted at /doctor/services, before the /doctor router, as the panels and
 * the reports are — so a price change is not first walked through the doctor
 * router's own guards on its way here.
 *
 * ---- Who may set a price -------------------------------------------------
 *
 * MANAGE_STAFF, which is the grant the owner and the practice manager hold.
 * Not PRESCRIBE and not VIEW_PATIENT: what a clinic charges is a business
 * decision taken by whoever runs the business, and a locum with prescribing
 * rights has no business raising the follow-up fee. Reading the list is open
 * to any doctor at the practice, because a doctor about to book somebody needs
 * to know what it will cost them.
 *
 * ---- What no service means -----------------------------------------------
 *
 * That the app does not collect for this visit. Every clinic here takes money
 * at the desk in cash today and nothing in the app has ever recorded it, so a
 * practice with no services is the normal state and not a misconfiguration.
 * It is specifically *not* "free": the app saying a visit is free when the desk
 * is about to ask for five hundred rupees is worse than the app saying nothing.
 *
 * ---- Deleting ------------------------------------------------------------
 *
 * A service that has been booked against is withdrawn, never removed. The
 * booking keeps its own copy of the amount, but the row is what says what that
 * amount was *for*, and a receipt whose service has vanished cannot be read.
 */
const router = Router();
router.use(requireAuth, requireDoctor);

const modes = ['in_clinic', 'teleconsult', 'both'];

const body = z.object({
  name: z.string().trim().min(2).max(80),
  mode: z.enum(modes).default('both'),
  /// Paise, integer. Rupees would arrive as a float and 499.99 would be
  /// stored as 49998.999999999996 paise.
  amountPaise: z.number().int().min(0).max(10_000_000),
  durationMinutes: z.number().int().min(5).max(240).nullish(),
  note: z.string().trim().max(240).nullish(),
  /// Null is the practice's own rate; an id is one doctor's.
  doctorId: z.string().nullish(),
  isActive: z.boolean().optional(),
});

/**
 * What the audit row says beyond who did it.
 *
 * The middleware records the actor, the action and the id, which is the right
 * amount for most writes. For a price it is not: the question somebody asks
 * three months later is "who raised the follow-up fee, and from what" — so the
 * figures go in the row too, both sides of a change. See middleware/audit.js.
 */
function trail(req, { service, practiceId, meta }) {
  req.auditResourceId = service?._id;
  req.auditMeta = { practice: String(practiceId), ...meta };
}

function serialise(s) {
  return {
    id: s._id,
    name: s.name,
    mode: s.mode,
    amountPaise: s.amountPaise,
    amountRupees: rupeesOf(s.amountPaise),
    durationMinutes: s.durationMinutes ?? null,
    note: s.note ?? null,
    doctorId: s.doctor ?? null,
    isActive: s.isActive !== false,
  };
}

/**
 * The practice's services.
 *
 * Withdrawn ones are included for whoever is editing the list and left out for
 * everybody else — a patient offered a service the clinic has stopped doing is
 * a patient who turns up for it.
 */
router.get(
  '/',
  validate({ query: z.object({ includeWithdrawn: z.enum(['0', '1']).default('0') }) }),
  asyncHandler(async (req, res) => {
    const practiceId = await practiceOf(req);
    if (!practiceId) throw noPractice();

    const rows = await Service.find({
      practice: practiceId,
      ...(q(req).includeWithdrawn === '1' ? {} : { isActive: true }),
    })
      .sort({ amountPaise: 1, name: 1 })
      .lean();

    res.json({ items: rows.map(serialise) });
  }),
);

router.post(
  '/',
  requirePermission(PERMISSIONS.MANAGE_STAFF),
  validate({ body }),
  audit('create', 'Service'),
  asyncHandler(async (req, res) => {
    const practiceId = await practiceOf(req);
    if (!practiceId) throw noPractice();

    const { name, mode, amountPaise, durationMinutes, note, doctorId } = req.body;

    let created;
    try {
      created = await Service.create({
        practice: practiceId,
        doctor: doctorId || null,
        name,
        mode,
        amountPaise,
        durationMinutes: durationMinutes ?? null,
        note: note || null,
      });
    } catch (err) {
      // The unique index, not a race we can win by checking first.
      if (err?.code === 11000) {
        throw conflict('There is already a service with that name.');
      }
      throw err;
    }

    trail(req, {
      service: created,
      practiceId,
      meta: { name, amountPaise, mode },
    });
    res.status(201).json({ service: serialise(created) });
  }),
);

router.patch(
  '/:id',
  requirePermission(PERMISSIONS.MANAGE_STAFF),
  validate({ body: body.partial() }),
  audit('update', 'Service'),
  asyncHandler(async (req, res) => {
    const practiceId = await practiceOf(req);
    if (!practiceId) throw noPractice();

    // Scoped in the query, not checked after: a find by id alone would hand
    // another practice's price list to whoever asked for it by id.
    const service = await Service.findOne({
      _id: req.params.id,
      practice: practiceId,
    });
    if (!service) throw notFound('Service not found');

    const before = {
      name: service.name,
      amountPaise: service.amountPaise,
      mode: service.mode,
      isActive: service.isActive,
    };

    for (const field of ['name', 'mode', 'amountPaise', 'isActive']) {
      if (req.body[field] !== undefined) service[field] = req.body[field];
    }
    if (req.body.durationMinutes !== undefined) {
      service.durationMinutes = req.body.durationMinutes ?? null;
    }
    if (req.body.note !== undefined) service.note = req.body.note || null;
    if (req.body.doctorId !== undefined) service.doctor = req.body.doctorId || null;

    try {
      await service.save();
    } catch (err) {
      if (err?.code === 11000) {
        throw conflict('There is already a service with that name.');
      }
      throw err;
    }

    trail(req, {
      service,
      practiceId,
      meta: { before, after: serialise(service) },
    });
    res.json({ service: serialise(service) });
  }),
);

router.delete(
  '/:id',
  requirePermission(PERMISSIONS.MANAGE_STAFF),
  // 'update' rather than 'delete' is wrong half the time and right the other
  // half, so the row says which happened in its meta: a service bookings
  // refer to is withdrawn, not removed.
  audit('delete', 'Service'),
  asyncHandler(async (req, res) => {
    const practiceId = await practiceOf(req);
    if (!practiceId) throw noPractice();

    const service = await Service.findOne({
      _id: req.params.id,
      practice: practiceId,
    });
    if (!service) throw notFound('Service not found');

    const booked = await Appointment.countDocuments({ service: service._id });
    if (booked > 0) {
      // Withdrawn instead, and said so rather than silently doing something
      // else than what was asked.
      service.isActive = false;
      await service.save();
      trail(req, {
        service,
        practiceId,
        meta: { withdrawn: true, booked },
      });
      return res.json({
        service: serialise(service),
        withdrawn: true,
        message:
          `${booked} ${booked === 1 ? 'appointment has' : 'appointments have'} ` +
          'been booked against this service, so it has been withdrawn rather ' +
          'than deleted. It will not be offered again.',
      });
    }

    await service.deleteOne();
    trail(req, {
      service,
      practiceId,
      meta: { removed: true, name: service.name, amountPaise: service.amountPaise },
    });
    res.json({ deleted: true });
  }),
);

export default router;
