/**
 * Fills a test doctor's practice in, so the doctor panel has something to show.
 *
 * ---- Why this exists ------------------------------------------------------
 *
 * Half the doctor panel is correctly invisible on an empty practice. No
 * published hours means "Not taking bookings", no slots, and an Assign-time
 * sheet with no day to book into. No services means the fee rows are empty. No
 * registration number means a prescription that can be questioned at the
 * counter. None of that is a bug and none of it can be looked at.
 *
 * So this writes the four things the panel needs to come alive: a registration
 * number, a second location, published hours at both, a price list, and a few
 * appointments across today and the week.
 *
 * ---- What it refuses to do -----------------------------------------------
 *
 * It will not touch a doctor whose name does not say "test". A seeder that can
 * be pointed at a real clinician is a seeder that will one day write a made-up
 * registration number onto somebody's prescriptions. `--doctor=<id>` overrides
 * the name check only with `--force`, and says so.
 *
 * The registration number it writes is deliberately NOT a plausible council
 * number. `TEST-NOT-A-REAL-REGISTRATION` prints on a prescription PDF exactly
 * as stored, and anybody who sees one must be able to tell at a glance that it
 * is not a credential. A realistic "WBMC 64213" in a staging database is one
 * restore away from looking real.
 *
 * It creates no patients. Appointments are seeded only against patients the
 * practice already has, because inventing a patient record — even a fake one —
 * puts a person-shaped row in a clinical database.
 *
 *   node scripts/seedDoctorTestData.js                  # report only
 *   node scripts/seedDoctorTestData.js --apply
 *   node scripts/seedDoctorTestData.js --apply --doctor=<userId> --force
 *   node scripts/seedDoctorTestData.js --apply --only=hours,services
 */
import mongoose from 'mongoose';

import { env } from '../src/config/env.js';
import { User, ROLES } from '../src/models/User.js';
import { Practice } from '../src/models/Practice.js';
import { Membership } from '../src/models/Membership.js';
import { Clinic } from '../src/models/Clinic.js';
import { Availability } from '../src/models/Availability.js';
import { Service } from '../src/models/Service.js';
import { Appointment } from '../src/models/Appointment.js';
import { Enrollment } from '../src/models/Enrollment.js';
import { capabilitiesOfPractice, CAPABILITIES } from '../src/services/capabilities.js';

const apply = process.argv.includes('--apply');
const force = process.argv.includes('--force');

function arg(name) {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : null;
}

const only = (arg('only') ?? '').split(',').filter(Boolean);
const wants = (step) => only.length === 0 || only.includes(step);

/** Said once at the end, so a report run reads as a list of intentions. */
const did = [];
const skipped = [];

/**
 * A registration number nobody can mistake for one.
 *
 * It goes on the prescription PDF verbatim — see the letterhead in
 * services/prescriptionPdf.js. A staging database restored into the wrong
 * place must not hand anybody a credential that reads as genuine.
 */
const TEST_REGISTRATION = 'TEST-NOT-A-REAL-REGISTRATION';

/** Mon–Sat mornings, Mon/Wed/Fri evenings. Enough to exercise a week. */
const WEEK = [
  ...[1, 2, 3, 4, 5, 6].map((d) => ({ dayOfWeek: d, start: '09:00', end: '13:00' })),
  ...[1, 3, 5].map((d) => ({ dayOfWeek: d, start: '17:00', end: '20:00' })),
];

/*
 * All in clinic. MedPin sees patients in a building: a teleconsult has no
 * `Clinic` row, so there is nowhere for video hours to live and no published
 * day to book one into. A seeded video price would be a visit the product
 * cannot arrange.
 */
const PRICES = [
  { name: 'First consultation', amountPaise: 60000, durationMinutes: 20 },
  { name: 'Follow-up', amountPaise: 30000, durationMinutes: 15 },
  { name: 'Report review', amountPaise: 20000, durationMinutes: 10 },
  { name: 'Dressing or injection', amountPaise: 15000, durationMinutes: 10 },
];

async function main() {
  await mongoose.connect(env.MONGODB_URI);

  const doctor = await findDoctor();
  if (!doctor) return;

  // `currentFilter(user)` with no practice means "their current membership,
  // wherever it is" — see models/Membership.js. A test doctor has one.
  const membership = await Membership.findOne(
    Membership.currentFilter(doctor._id),
  ).lean();

  const practice = membership?.practice
    ? await Practice.findById(membership.practice)
    : null;
  if (!practice) {
    console.log(
      `${doctor.name} holds no current membership, so there is no practice to fill in. ` +
        'Add them to one first.',
    );
    return;
  }

  console.log(`Doctor:   ${doctor.name} (${doctor._id})`);
  console.log(`Practice: ${practice.name} — ${practice.practiceType ?? 'no type'} on the ${practice.plan} plan\n`);

  if (wants('registration')) await seedRegistration(doctor);
  const rooms = wants('locations') ? await seedLocations(practice) : await openRooms(practice);
  if (wants('hours')) await seedHours(doctor, rooms);
  if (wants('services')) await seedServices(practice, doctor);
  if (wants('appointments')) await seedAppointments(practice, doctor, rooms);

  console.log('');
  if (!apply) {
    console.log('Nothing was written. Re-run with --apply.');
    console.log('Would do:');
    for (const line of did) console.log(`  · ${line}`);
  } else {
    console.log('Done:');
    for (const line of did) console.log(`  · ${line}`);
  }
  if (skipped.length) {
    console.log('Left alone:');
    for (const line of skipped) console.log(`  · ${line}`);
  }
}

/** The test doctor, and nobody else unless somebody insists. */
async function findDoctor() {
  const id = arg('doctor');
  if (id) {
    const row = await User.findById(id);
    if (!row) {
      console.log(`No user with id ${id}.`);
      return null;
    }
    if (!/test/i.test(row.name ?? '') && !force) {
      console.log(
        `${row.name} does not look like a test account. This script writes a fake\n` +
          'registration number and invented prices. Pass --force if you are certain.',
      );
      return null;
    }
    return row;
  }

  const candidates = await User.find({
    role: ROLES.DOCTOR,
    name: /test/i,
    isActive: true,
  }).select('name phone');

  if (candidates.length === 1) return candidates[0];
  if (candidates.length === 0) {
    console.log(
      'No active doctor with "test" in their name. Pass --doctor=<userId> (and --force\n' +
        'if the account is not a test one).',
    );
    return null;
  }
  console.log('Several test doctors — pass --doctor=<userId>:');
  for (const c of candidates) console.log(`  ${c._id}  ${c.name}  ${c.phone}`);
  return null;
}

async function seedRegistration(doctor) {
  if ((doctor.registrationNo ?? '').trim()) {
    skipped.push(`registration number (already ${doctor.registrationNo})`);
    return;
  }
  did.push(`set the registration number to ${TEST_REGISTRATION}`);
  if (!apply) return;

  doctor.registrationNo = TEST_REGISTRATION;
  doctor.council = 'Test Council (not a real registry)';
  doctor.registrationYear = 2004;
  if (!doctor.qualifications) doctor.qualifications = 'MBBS, MD';
  if (!doctor.practisingSince) doctor.practisingSince = 2004;
  await doctor.save();
}

/** Every open location of the practice. */
async function openRooms(practice) {
  return Clinic.find({ practice: practice._id, isActive: true });
}

/**
 * A second location, where the practice is allowed one.
 *
 * The cap is real: `POST /clinics` refuses a second location without the
 * MULTI_LOCATION capability, which a plain clinic on the Essential plan does
 * not hold. This script honours the same limit rather than walking past it —
 * a seeded state the product would refuse to create teaches nothing.
 */
async function seedLocations(practice) {
  const rooms = await openRooms(practice);
  const cap = practice.limits?.locations ?? null;

  /*
   * The capability, not only the number — and this script got that wrong.
   *
   * It checked `limits.locations` and nothing else, so it happily wrote a
   * second location into a practice of type `clinic`, which never holds
   * MULTI_LOCATION whatever its plan. `POST /clinics` would have refused it.
   * The result was a practice showing two locations under the words "this
   * practice is set up for a single location" — a state the product cannot
   * reach on its own, which is exactly what this script promised not to make.
   */
  if (rooms.length >= 1) {
    const held = capabilitiesOfPractice(practice);
    if (!held.includes(CAPABILITIES.MULTI_LOCATION)) {
      skipped.push(
        `a second location — a ${practice.practiceType ?? 'practice of no type'} ` +
          'does not run from more than one building, whatever its plan. ' +
          'Change the practice type to a polyclinic or a hospital first.',
      );
      return rooms;
    }
  }

  if (cap != null && rooms.length >= cap) {
    skipped.push(
      `a second location — the ${practice.plan} plan allows ${cap} and there ${rooms.length === 1 ? 'is' : 'are'} ${rooms.length}`,
    );
    return rooms;
  }
  if (rooms.some((c) => /salt lake/i.test(c.name))) {
    skipped.push('the Salt Lake location (already there)');
    return rooms;
  }

  did.push('add "City Care Clinic — Salt Lake"');
  if (!apply) return rooms;

  const made = await Clinic.create({
    practice: practice._id,
    name: 'City Care Clinic — Salt Lake',
    kind: 'clinic',
    addressLine: 'DD-24, Sector 1, Salt Lake',
    city: 'Kolkata',
    phone: '+913340001234',
    landmark: 'Opposite the City Centre',
    isActive: true,
    weeklyHours: [],
  });
  return [...rooms, made];
}

/**
 * Published hours, which is what makes a slot exist.
 *
 * Without these the profile says "Not taking bookings", the queue is empty and
 * Assign time has no day to offer — which is exactly the state the panel is in
 * today and the reason most of it cannot be looked at.
 */
async function seedHours(doctor, rooms) {
  if (!rooms.length) {
    skipped.push('hours (the practice has no open location)');
    return;
  }
  for (const room of rooms) {
    const existing = await Availability.findOne({ doctor: doctor._id, location: room._id });
    if (existing?.weeklyHours?.length) {
      skipped.push(`hours at ${room.name} (already published)`);
      continue;
    }
    did.push(`publish Mon–Sat 9–1 (+ Mon/Wed/Fri 5–8) at ${room.name}, 15-minute slots`);
    if (!apply) continue;

    await Availability.findOneAndUpdate(
      { doctor: doctor._id, location: room._id },
      {
        $set: {
          doctor: doctor._id,
          location: room._id,
          slotMinutes: 15,
          weeklyHours: WEEK,
          isActive: true,
          // The three the app can set and the server does not yet enforce —
          // seeded so the round-trip is visible once diaryOut returns them.
          patientsPerSlot: 1,
          walkInPlaces: 2,
          breakMinutes: 0,
        },
      },
      { upsert: true, new: true },
    );
  }
}

async function seedServices(practice, doctor) {
  for (const p of PRICES) {
    const existing = await Service.findOne({ practice: practice._id, name: p.name });
    if (existing) {
      skipped.push(`"${p.name}" (already priced at ₹${existing.amountPaise / 100})`);
      continue;
    }
    did.push(`price "${p.name}" at ₹${p.amountPaise / 100}`);
    if (!apply) continue;

    await Service.create({
      practice: practice._id,
      doctor: doctor._id,
      name: p.name,
      mode: 'in_clinic',
      amountPaise: p.amountPaise,
      durationMinutes: p.durationMinutes,
      isActive: true,
    });
  }
}

/**
 * A few appointments, against patients this practice already has.
 *
 * No patient is created. A fake person in a clinical database is a row
 * somebody will eventually open, ring, or count — and there is no way to tell
 * it from a real one a month later.
 */
async function seedAppointments(practice, doctor, rooms) {
  const room = rooms[0];
  if (!room) {
    skipped.push('appointments (no open location)');
    return;
  }

  const enrolled = await Enrollment.find({ practice: practice._id })
    .select('patient')
    .limit(6)
    .lean();
  const patientIds = [...new Set(enrolled.map((e) => String(e.patient)))];

  if (!patientIds.length) {
    skipped.push(
      'appointments — this practice has no enrolled patients, and this script will not invent one',
    );
    return;
  }

  const already = await Appointment.countDocuments({
    practice: practice._id,
    doctor: doctor._id,
    status: { $in: ['confirmed', 'checked_in'] },
    scheduledFor: { $gte: startOfToday() },
  });
  if (already >= 3) {
    skipped.push(`appointments (${already} already booked from today onward)`);
    return;
  }

  // Today mid-morning, this afternoon, and two later in the week — enough to
  // put something in the queue, in Today, and in Upcoming at once.
  const when = [
    at(0, 10, 0),
    at(0, 11, 30),
    at(1, 9, 30),
    at(3, 10, 0),
  ];

  for (const [i, slot] of when.entries()) {
    const patient = patientIds[i % patientIds.length];
    const clash = await Appointment.findOne({
      doctor: doctor._id,
      scheduledFor: slot,
      status: { $nin: ['cancelled', 'no_show'] },
    });
    if (clash) {
      skipped.push(`an appointment at ${slot.toISOString()} (something is already there)`);
      continue;
    }
    did.push(`book a patient at ${slot.toISOString()}`);
    if (!apply) continue;

    await Appointment.create({
      patient,
      doctor: doctor._id,
      practice: practice._id,
      clinic: room._id,
      mode: 'in_clinic',
      scheduledFor: slot,
      durationMinutes: 15,
      status: 'confirmed',
      reason: 'Seeded for testing',
    });
  }
}

function startOfToday() {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d;
}

function at(daysFromNow, hour, minute) {
  const d = startOfToday();
  d.setDate(d.getDate() + daysFromNow);
  d.setHours(hour, minute, 0, 0);
  return d;
}

main()
  .then(() => mongoose.disconnect())
  .catch(async (err) => {
    console.error(err);
    await mongoose.disconnect().catch(() => {});
    process.exitCode = 1;
  });
