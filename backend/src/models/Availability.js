import mongoose from 'mongoose';
import { TIME_RE, DATE_RE } from '../utils/clinicTime.js';

const timeValidator = { validator: (v) => TIME_RE.test(v), message: 'time must be HH:mm (24h)' };

const weeklyHoursSchema = new mongoose.Schema(
  {
    dayOfWeek: { type: Number, min: 0, max: 6, required: true }, // 0 = Sunday
    start: { type: String, required: true, validate: timeValidator },
    end: { type: String, required: true, validate: timeValidator },
  },
  { _id: false },
);

const windowSchema = new mongoose.Schema(
  {
    start: { type: String, required: true, validate: timeValidator },
    end: { type: String, required: true, validate: timeValidator },
  },
  { _id: false },
);

const overrideSchema = new mongoose.Schema(
  {
    date: { type: String, required: true, match: DATE_RE }, // 'YYYY-MM-DD'
    isClosed: { type: Boolean, default: false },
    windows: { type: [windowSchema], default: [] },
    note: { type: String, maxlength: 200 },
  },
  { _id: false },
);

/**
 * When a particular doctor sits at a particular location.
 *
 * ---- Why the hours moved off the clinic ---------------------------------
 *
 * `Clinic.weeklyHours` describes when the *building* is open, which is the same
 * thing as the doctor's diary only while there is one doctor. A polyclinic with
 * eight of them has one building and eight diaries, and hours on the location
 * would give all eight the same one — booking a cardiologist into a slot the
 * dermatologist is sitting in.
 *
 * So availability is a row per doctor per location. Dr. Dey at Salt Lake on
 * Mondays is one row; the same doctor at Behala on Thursday evenings is
 * another.
 *
 * ---- The shape is deliberately identical to Clinic's --------------------
 *
 * `weeklyHours`, `overrides` and `slotMinutes` carry exactly the field names
 * the clinic uses, because [services/scheduling.js] reads those three and
 * nothing else. That makes an availability row a drop-in for a clinic in the
 * slot engine — the pure functions did not change at all, and the fallback
 * costs one line rather than a parallel code path.
 */
const availabilitySchema = new mongoose.Schema(
  {
    doctor: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },

    /// The place. Still called `Clinic` in the codebase; it is the location.
    location: { type: mongoose.Schema.Types.ObjectId, ref: 'Clinic', required: true, index: true },

    /// Per doctor, not per building: a consultant may take 20 minutes where a
    /// general clinic takes 10, in the same room on different days.
    slotMinutes: { type: Number, default: 15, min: 5, max: 120 },

    /*
     * The rest of how a sitting is cut up (`Profile-Schedule`).
     *
     * ---- Why these live beside slotMinutes -------------------------------
     *
     * Because the slot list is built from them together, and because they are
     * the doctor's at this location rather than the building's: a consultant
     * seeing four patients an hour in the same room another doctor sees twelve
     * in is the ordinary case.
     *
     * `patientsPerSlot` above one is deliberate double-booking — a clinic that
     * runs a queue rather than appointments. `walkInPlaces` are held back from
     * the published list, so the last of them is the first walk-in's: they are
     * taken off the END of each sitting, not the start, because a doctor who
     * runs late loses the end of the session and not the morning.
     * `breakMinutes` is added after each patient, so a 15-minute slot with a
     * 5-minute break starts one patient every 20.
     */
    patientsPerSlot: { type: Number, default: 1, min: 1, max: 10 },
    walkInPlaces: { type: Number, default: 0, min: 0, max: 50 },
    breakMinutes: { type: Number, default: 0, min: 0, max: 60 },

    weeklyHours: { type: [weeklyHoursSchema], default: [] },
    overrides: { type: [overrideSchema], default: [] },

    /// Soft-disable, so appointments already booked against this diary keep a
    /// valid reference when a doctor stops sitting at a location.
    isActive: { type: Boolean, default: true, index: true },
  },
  { timestamps: true },
);

/// One diary per doctor per location. A second row is a duplicate, not a second
/// sitting — several sittings in a week are several `weeklyHours` entries.
availabilitySchema.index({ doctor: 1, location: 1 }, { unique: true });

/// "Who sits here, and when" — the query behind a location's booking page.
availabilitySchema.index({ location: 1, isActive: 1 });

availabilitySchema.methods.toPublic = function toPublic() {
  return {
    id: String(this._id),
    doctor: String(this.doctor),
    location: String(this.location),
    slotMinutes: this.slotMinutes,
    // The same three `diaryOut` returns. This serialiser is unused on that
    // path, but a shape that disagrees with the one the app actually reads
    // is a trap for whoever wires the next caller.
    patientsPerSlot: this.patientsPerSlot ?? 1,
    walkInPlaces: this.walkInPlaces ?? 0,
    breakMinutes: this.breakMinutes ?? 0,
    weeklyHours: (this.weeklyHours ?? [])
      .map((w) => ({ dayOfWeek: w.dayOfWeek, start: w.start, end: w.end }))
      .sort((a, b) => a.dayOfWeek - b.dayOfWeek || a.start.localeCompare(b.start)),
    overrides: (this.overrides ?? []).map((o) => ({
      date: o.date,
      isClosed: o.isClosed,
      windows: (o.windows ?? []).map((w) => ({ start: w.start, end: w.end })),
      note: o.note ?? null,
    })),
    isActive: this.isActive,
  };
};

export const Availability = mongoose.model('Availability', availabilitySchema);
