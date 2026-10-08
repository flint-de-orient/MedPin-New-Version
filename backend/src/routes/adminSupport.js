import { Router } from 'express';
import { z } from 'zod';

import { validate, q } from '../middleware/validate.js';
import { asyncHandler, notFound } from '../middleware/errors.js';
import { AdminAuditLog } from '../models/AdminAuditLog.js';
import { SupportRequest, SUPPORT_STATE, SUPPORT_TOPIC } from '../models/SupportRequest.js';
import { paged, pageParams } from '../utils/pagination.js';

/**
 * The operator's side of the clinics' help requests.
 *
 * Nested inside admin.js, after `requireAdmin`, for the reason billing and the
 * application queue are: a sibling mount in routes/index.js would not inherit
 * the guard, and this surface reads what clinics have written to us.
 *
 * ---- Named, unlike patient feedback --------------------------------------
 *
 * adminFeedback.js deliberately hides who a patient is. This does the
 * opposite, and has to: a support answer is usually "your letterhead has no
 * registration number" or "that doctor has no membership at Salt Lake", and
 * neither can be said to an anonymous row. So the practice and the clinician
 * are both named here.
 *
 * It still holds no clinical data. The form that writes these asks for none
 * and says not to include a patient's name — which is as far as a route can
 * go, since the message is free text.
 */
const router = Router();

router.get(
  '/',
  validate({
    query: pageParams.and(
      z.object({
        state: z.enum(Object.values(SUPPORT_STATE)).optional(),
        topic: z.enum(Object.values(SUPPORT_TOPIC)).optional(),
      }),
    ),
  }),
  asyncHandler(async (req, res) => {
    const { page, limit, skip } = q(req);
    const filter = {
      ...(req.query.state ? { state: req.query.state } : {}),
      ...(req.query.topic ? { topic: req.query.topic } : {}),
    };

    const [rows, total] = await Promise.all([
      SupportRequest.find(filter)
        // Oldest first, because this is a queue and the oldest unanswered
        // request is the one somebody has been waiting on longest. Newest
        // first would be a list that quietly buries the worst case.
        .sort({ createdAt: 1 })
        .skip(skip)
        .limit(limit)
        .populate('practice', 'name')
        .populate('raisedBy', 'name phone role')
        .lean(),
      SupportRequest.countDocuments(filter),
    ]);

    await AdminAuditLog.record({
      admin: req.admin,
      action: 'admin.support.list',
      resource: 'SupportRequest',
      req,
    });

    res.json(paged(rows.map(forOperator), { page, limit, total }));
  }),
);

router.post(
  '/:id/replies',
  validate({
    body: z.object({
      text: z.string().trim().min(2).max(4000),
      /*
       * Whether this answer finishes it.
       *
       * The operator decides, rather than a reply always closing: "can you
       * confirm which branch" is an answer that leaves the row open, and
       * closing it there would drop the clinic out of the queue mid-sentence.
       */
      close: z.boolean().optional(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const row = await SupportRequest.findById(req.params.id);
    if (!row) throw notFound('Request not found');

    row.replies.push({ text: req.body.text, by: 'medpin' });
    row.lastReplyAt = new Date();
    row.state = req.body.close ? SUPPORT_STATE.CLOSED : SUPPORT_STATE.ANSWERED;
    await row.save();

    await AdminAuditLog.record({
      admin: req.admin,
      action: req.body.close ? 'admin.support.close' : 'admin.support.reply',
      resource: 'SupportRequest',
      resourceId: row._id,
      req,
    });

    res.json({ request: row.toClinic() });
  }),
);

/**
 * One row as the console shows it.
 *
 * The whole thread, because an operator picking up somebody else's
 * conversation needs what was already said — a queue that showed only the
 * first message is a queue where the same question is answered twice.
 */
function forOperator(r) {
  return {
    id: String(r._id),
    reference: String(r._id).slice(-6).toUpperCase(),
    topic: r.topic,
    state: r.state,
    message: r.message,
    appVersion: r.appVersion ?? null,
    platform: r.platform ?? null,
    createdAt: r.createdAt,
    lastReplyAt: r.lastReplyAt ?? null,
    practice: r.practice ? { id: String(r.practice._id), name: r.practice.name } : null,
    raisedBy: r.raisedBy
      ? {
          id: String(r.raisedBy._id),
          name: r.raisedBy.name,
          phone: r.raisedBy.phone,
          role: r.raisedBy.role,
        }
      : null,
    replies: (r.replies ?? []).map((reply) => ({
      id: String(reply._id),
      text: reply.text,
      by: reply.by,
      at: reply.at,
    })),
  };
}

export default router;
