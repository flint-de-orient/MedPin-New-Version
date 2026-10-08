import { Router } from 'express';
import { z } from 'zod';

import { requireAuth, requireRole } from '../middleware/auth.js';
import { practiceOf } from '../middleware/practiceScope.js';
import { validate, q } from '../middleware/validate.js';
import { asyncHandler, notFound, badRequest } from '../middleware/errors.js';
import { audit } from '../middleware/audit.js';
import { CLINICIAN_ROLES } from '../models/User.js';
import { SupportRequest, SUPPORT_TOPIC, SUPPORT_STATE } from '../models/SupportRequest.js';
import { paged, pageParams } from '../utils/pagination.js';

/**
 * A clinician asking MedPin for help.
 *
 * ---- Why this exists rather than an email address ------------------------
 *
 * The Help row on the profile had nothing behind it, and the obvious fix — put
 * support@ in the copy — is worse than it looks. An address in the app is an
 * address that has to be monitored by somebody, forever, and the first time it
 * is not, a doctor who cannot print a prescription writes into silence. A row
 * in a queue the operator console already shows is a message with somewhere to
 * land and a state somebody can be held to.
 *
 * It also arrives with the three facts every support conversation spends its
 * first day establishing: which practice, which account, which build.
 *
 * ---- Who may raise one ---------------------------------------------------
 *
 * Any clinician. Not a permission: needing help is not a privilege, and a
 * receptionist locked out on a Monday morning is precisely the person who
 * must be able to say so. Patients have their own route — see
 * routes/feedback.js — because what they need to say and who should read it
 * are both different.
 *
 * ---- What a clinic may do to a row it raised ------------------------------
 *
 * Add to it, and close it. Not edit what it already said and not delete it: a
 * support thread that can be rewritten is a support thread neither side can
 * rely on, and the operator may already have acted on the first message.
 */
const router = Router();

router.use(requireAuth, requireRole(...CLINICIAN_ROLES));

const TOPICS = Object.values(SUPPORT_TOPIC);

router.get(
  '/',
  validate({ query: pageParams }),
  audit('read', 'SupportRequest'),
  asyncHandler(async (req, res) => {
    const { page, limit, skip } = q(req);

    /*
     * Theirs, by account and not by practice.
     *
     * A support request names the person who raised it and may say "I cannot
     * sign in" or "my colleague has locked me out" — which is about a
     * colleague. Scoping by practice would hand every clinician at the
     * practice everything anybody there has ever asked us, and some of it is
     * about them.
     */
    const filter = { raisedBy: req.user._id };

    const [rows, total] = await Promise.all([
      SupportRequest.find(filter).sort({ createdAt: -1 }).skip(skip).limit(limit),
      SupportRequest.countDocuments(filter),
    ]);

    res.json(paged(rows.map((r) => r.toClinic()), { page, limit, total }));
  }),
);

router.post(
  '/',
  validate({
    body: z.object({
      topic: z.enum(TOPICS),
      message: z.string().trim().min(10).max(4000),
      /*
       * The build, sent by the app rather than guessed from a header. A
       * version string is the first thing support asks for and the last thing
       * a doctor knows.
       */
      appVersion: z.string().trim().max(40).optional(),
      platform: z.string().trim().max(40).optional(),
    }),
  }),
  audit('create', 'SupportRequest'),
  asyncHandler(async (req, res) => {
    const practiceId = await practiceOf(req);

    const row = await SupportRequest.create({
      practice: practiceId ?? null,
      raisedBy: req.user._id,
      topic: req.body.topic,
      message: req.body.message,
      appVersion: req.body.appVersion ?? null,
      platform: req.body.platform ?? null,
      state: SUPPORT_STATE.OPEN,
    });

    req.auditResourceId = row._id;
    /*
     * The topic and the build, never the message.
     *
     * The audit log is read by more people than the row is, and a clinician
     * typing freely into a help form may put a patient's name in it despite
     * the form asking them not to. What the log needs is that somebody asked
     * for help about scheduling on 1.0.73.
     */
    req.auditMeta = {
      ...req.auditMeta,
      topic: row.topic,
      appVersion: row.appVersion,
    };

    res.status(201).json({ request: row.toClinic() });
  }),
);

router.post(
  '/:id/replies',
  validate({ body: z.object({ text: z.string().trim().min(2).max(4000) }) }),
  audit('update', 'SupportRequest'),
  asyncHandler(async (req, res) => {
    const row = await mine(req);

    if (row.state === SUPPORT_STATE.CLOSED) {
      throw badRequest(
        'This request is closed. Raise a new one and mention the old reference.',
      );
    }

    row.replies.push({ text: req.body.text, by: 'clinic', author: req.user._id });
    /*
     * Back to open, because the clinic has answered and the ball is ours
     * again. A row left as `answered` after the clinic replied is a row that
     * drops out of the operator's queue with somebody still waiting.
     */
    row.state = SUPPORT_STATE.OPEN;
    await row.save();

    req.auditResourceId = row._id;
    req.auditMeta = { ...req.auditMeta, replies: row.replies.length };

    res.json({ request: row.toClinic() });
  }),
);

router.post(
  '/:id/close',
  audit('update', 'SupportRequest'),
  asyncHandler(async (req, res) => {
    const row = await mine(req);

    // Idempotent: closing a closed request is the state it is already in, and
    // answering it with a refusal makes a double tap look like a failure.
    if (row.state !== SUPPORT_STATE.CLOSED) {
      row.state = SUPPORT_STATE.CLOSED;
      await row.save();
    }

    req.auditResourceId = row._id;
    req.auditMeta = { ...req.auditMeta, state: row.state };

    res.json({ request: row.toClinic() });
  }),
);

/**
 * The row, if it is this account's.
 *
 * `notFound` rather than a refusal for somebody else's: confirming that an id
 * exists is itself an answer, and these ids are short enough to guess at.
 */
async function mine(req) {
  const row = await SupportRequest.findOne({
    _id: req.params.id,
    raisedBy: req.user._id,
  });
  if (!row) throw notFound('Request not found');
  return row;
}

export default router;
