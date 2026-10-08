import mongoose from 'mongoose';

/**
 * A clinician asking MedPin for help, and what we said back.
 *
 * ---- Why this is not Feedback ---------------------------------------------
 *
 * `Feedback` is a patient's, and the platform reads it without the patient's
 * identity — see the note at the top of that model. This is the opposite on
 * both counts. It is a clinician's, and the operator needs to know exactly who
 * and which practice, because the answer is usually "your letterhead has no
 * registration number" or "that doctor has no membership at Salt Lake". An
 * anonymised support request is a support request nobody can act on.
 *
 * Keeping them in one collection would have meant one queue where half the
 * rows must be de-identified and half must not, and the de-identification
 * would eventually be applied to the wrong half.
 *
 * ---- No clinical data, and the form says so -------------------------------
 *
 * The message is free text typed by a clinician, so a patient's name can
 * physically end up in it. Nothing here asks for one, the form says not to
 * include one, and the operator console shows this alongside practice
 * administration rather than anything clinical. That is as far as a schema can
 * go; the rest is the copy on the form.
 */
export const SUPPORT_TOPIC = Object.freeze({
  /// Cannot sign in, lost a number, a colleague locked out.
  ACCESS: 'access',
  /// The letterhead, a registration number, a signature, a printed
  /// prescription that came out wrong.
  PRESCRIBING: 'prescribing',
  /// Appointments, the diary, the queue, reminders.
  SCHEDULING: 'scheduling',
  /// A plan, an invoice, a payout that has not arrived.
  BILLING: 'billing',
  /// Something is broken.
  BUG: 'bug',
  /// Anything else.
  OTHER: 'other',
});

export const SUPPORT_STATE = Object.freeze({
  /// Nobody has looked at it.
  OPEN: 'open',
  /// An operator has replied and is waiting on the clinic.
  ANSWERED: 'answered',
  /// Done, by either side.
  CLOSED: 'closed',
});

const replySchema = new mongoose.Schema(
  {
    text: { type: String, required: true, trim: true, maxlength: 4000 },

    /**
     * Who wrote it — the clinic, or MedPin.
     *
     * Not a user id for the operator's side. An operator is a `PlatformAdmin`
     * and not a `User`, and a ref that pointed at two different collections
     * depending on `by` is a ref nothing can populate.
     */
    by: { type: String, enum: ['clinic', 'medpin'], required: true },

    /// The clinician who wrote it, when the clinic did.
    author: { type: mongoose.Schema.Types.ObjectId, ref: 'User', default: null },

    at: { type: Date, default: Date.now },
  },
  { _id: true },
);

const supportRequestSchema = new mongoose.Schema(
  {
    practice: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Practice',
      default: null,
      index: true,
    },

    /// Who asked. Required: a support request from nobody cannot be answered.
    raisedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },

    topic: {
      type: String,
      enum: Object.values(SUPPORT_TOPIC),
      required: true,
      index: true,
    },

    message: { type: String, required: true, trim: true, maxlength: 4000 },

    /**
     * What the handset was running.
     *
     * Taken from the request rather than asked for, because "which version are
     * you on" is the first question every support conversation wastes a day
     * on, and the answer a doctor gives is usually "the latest one".
     */
    appVersion: { type: String, trim: true, maxlength: 40, default: null },
    platform: { type: String, trim: true, maxlength: 40, default: null },

    state: {
      type: String,
      enum: Object.values(SUPPORT_STATE),
      default: SUPPORT_STATE.OPEN,
      index: true,
    },

    replies: { type: [replySchema], default: [] },

    /// When MedPin last wrote, so the clinic's own list can show an unread
    /// mark without a per-reply read receipt.
    lastReplyAt: { type: Date, default: null },
  },
  { timestamps: true },
);

/// The clinic's own list, newest first.
supportRequestSchema.index({ raisedBy: 1, createdAt: -1 });
/// The operator's queue: the open ones, oldest first.
supportRequestSchema.index({ state: 1, createdAt: 1 });

/** What the clinic's own app is shown. */
supportRequestSchema.methods.toClinic = function toClinic() {
  return {
    id: String(this._id),
    /*
     * A handle somebody can read out on the phone. The last six of the id,
     * which is short enough to say and long enough not to collide inside one
     * practice's own list.
     */
    reference: String(this._id).slice(-6).toUpperCase(),
    topic: this.topic,
    message: this.message,
    state: this.state,
    appVersion: this.appVersion ?? null,
    createdAt: this.createdAt,
    lastReplyAt: this.lastReplyAt ?? null,
    replies: (this.replies ?? []).map((r) => ({
      id: String(r._id),
      text: r.text,
      by: r.by,
      at: r.at,
    })),
  };
};

export const SupportRequest = mongoose.model('SupportRequest', supportRequestSchema);
