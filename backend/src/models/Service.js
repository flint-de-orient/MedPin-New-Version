import mongoose from 'mongoose';

/**
 * A consultation a practice offers, and what it charges for it.
 *
 * ---- Why a row and not a number on the clinic ----------------------------
 *
 * A single `consultationFee` on the practice was the obvious first move and is
 * wrong within a week: a first visit and a follow-up are not the same price, a
 * video call usually is not either, and a clinic with three doctors rarely has
 * one rate. The screen the design asks for says "5 services · in clinic and
 * video", so five rows is what it is.
 *
 * ---- What a fee here does NOT mean ---------------------------------------
 *
 * Nothing is charged by existing. A fee becomes money only when an appointment
 * is booked against this service — which copies the amount onto the booking,
 * because a price that changes next month must not change what last month's
 * patient was asked for. See `fee.amountPaise` on Appointment.
 *
 * ---- Paise ----------------------------------------------------------------
 *
 * Integer paise, never rupees as a float. 0.1 + 0.2 is not 0.3 in binary
 * floating point, and a fee is a number somebody is asked to pay. It is also
 * the unit Razorpay's API takes, so nothing has to be converted on the way out.
 */
const serviceSchema = new mongoose.Schema(
  {
    /// The practice that offers it. Never null: a fee belongs to whoever
    /// collects it, and a shared row would be a price set by the platform.
    practice: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Practice',
      required: true,
      index: true,
    },

    /// One doctor's own rate, or null for the practice's.
    ///
    /// Null is the common case and the one a single-doctor clinic never
    /// notices. A second doctor who charges differently gets rows of their
    /// own, and the lookup prefers theirs over the practice's.
    doctor: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
      index: true,
    },

    /// 'New consultation', 'Follow-up', 'Report review'.
    name: { type: String, required: true, trim: true, maxlength: 80 },

    /// Which kind of visit it is the price of.
    ///
    /// 'both' is one row covering a clinic visit and a video call at the same
    /// price, which is what most clinics start with.
    mode: {
      type: String,
      enum: ['in_clinic', 'teleconsult', 'both'],
      default: 'both',
      index: true,
    },

    /// Integer paise. Zero is a real answer — a free follow-up within a
    /// fortnight is a common arrangement — and is not the same as no fee set,
    /// which is a service that does not exist yet.
    amountPaise: { type: Number, required: true, min: 0, max: 10_000_000 },

    /// How long the visit is booked for, where it differs from the location's
    /// slot length. Null leaves the slot as published.
    durationMinutes: { type: Number, min: 5, max: 240, default: null },

    /// Shown under the name on the patient's side.
    note: { type: String, trim: true, maxlength: 240, default: null },

    /// A withdrawn service stays as a row, because bookings refer to it.
    isActive: { type: Boolean, default: true, index: true },
  },
  { timestamps: true },
);

/// One name per practice per doctor, so a list cannot show "Follow-up" twice.
serviceSchema.index(
  { practice: 1, doctor: 1, name: 1 },
  { unique: true, name: 'one_service_name_per_practice_doctor' },
);

export const Service = mongoose.models.Service || mongoose.model('Service', serviceSchema);

/** Rupees, for a screen. Integer where the paise divide, two places where not. */
export function rupeesOf(amountPaise) {
  return amountPaise % 100 === 0
    ? String(amountPaise / 100)
    : (amountPaise / 100).toFixed(2);
}
