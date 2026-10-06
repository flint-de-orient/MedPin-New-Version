import { test, describe, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import mongoose from 'mongoose';
import { MongoMemoryServer } from 'mongodb-memory-server';

/**
 * The consultation MIS.
 *
 * Every figure on the Reports tab is a count of rows this practice owns, so
 * what these tests pin is the counting: the window, whose rows are in it, and
 * what the summary refuses to make up when the data is not there.
 */

let mongod;
let buildConsultationSummary;
let Appointment;
let Prescription;
let Enrollment;
let User;
let Clinic;

const practice = new mongoose.Types.ObjectId();
const other = new mongoose.Types.ObjectId();
let doctor;
let colleague;
let patient;
let salt;

before(async () => {
  process.env.NODE_ENV = 'test';
  process.env.JWT_SECRET ??= 'test-secret-for-consultation-summary';
  mongod = await MongoMemoryServer.create();
  await mongoose.connect(mongod.getUri(), { dbName: 'mis_test' });

  ({ buildConsultationSummary } = await import('../src/services/consultationSummary.js'));
  ({ Appointment } = await import('../src/models/Appointment.js'));
  ({ Prescription } = await import('../src/models/Prescription.js'));
  ({ Enrollment } = await import('../src/models/Enrollment.js'));
  ({ User } = await import('../src/models/User.js'));
  ({ Clinic } = await import('../src/models/Clinic.js'));
});

after(async () => {
  await mongoose.disconnect();
  await mongod?.stop();
});

beforeEach(async () => {
  await Promise.all([
    Appointment.deleteMany({}),
    Prescription.deleteMany({}),
    Enrollment.deleteMany({}),
    User.deleteMany({}),
    Clinic.deleteMany({}),
  ]);
  doctor = await User.create({ name: 'Dr. Sen', phone: '+919800000001', role: 'doctor' });
  colleague = await User.create({ name: 'Dr. Mitra', phone: '+919800000002', role: 'doctor' });
  patient = await User.create({ name: 'Priya', phone: '+919800000003', role: 'patient' });
  salt = await Clinic.create({ name: 'City Care', city: 'Salt Lake', practice });
});

async function seen(when, { who = null, clinic = null, status = 'completed', minutes } = {}) {
  const called = minutes == null ? null : new Date(when.getTime());
  return Appointment.create({
    patient: patient._id,
    doctor: who?._id ?? doctor._id,
    practice,
    clinic: clinic?._id,
    status,
    scheduledFor: when,
    ...(called ? { calledAt: called } : {}),
    ...(minutes == null ? {} : { completedAt: new Date(when.getTime() + minutes * 60000) }),
  });
}

const window_ = { from: '2026-09-01', to: '2026-09-30' };

function summary(extra = {}) {
  return buildConsultationSummary({
    doctorId: doctor._id,
    practiceId: practice,
    ...window_,
    ...extra,
  });
}

describe('what the summary counts', () => {
  test('only this doctor, at this practice, inside the window', async () => {
    await seen(new Date('2026-09-10T10:00:00Z'));
    await seen(new Date('2026-09-20T10:00:00Z'));
    // A colleague's consultation, the same day, the same practice.
    await seen(new Date('2026-09-20T11:00:00Z'), { who: colleague });
    // This doctor, but the month before.
    await seen(new Date('2026-08-20T10:00:00Z'));
    // This doctor, in the window, but another practice's row.
    await Appointment.create({
      patient: patient._id,
      doctor: doctor._id,
      practice: other,
      status: 'completed',
      scheduledFor: new Date('2026-09-15T10:00:00Z'),
    });

    const out = await summary();
    assert.equal(out.kpis.consultations.value, 2);
    assert.equal(out.kpis.consultations.previous, 1, 'August is the comparison');
  });

  test('somebody who booked and never came is counted apart', async () => {
    await seen(new Date('2026-09-10T10:00:00Z'));
    await seen(new Date('2026-09-11T10:00:00Z'), { status: 'no_show' });

    const out = await summary();
    assert.equal(out.kpis.consultations.value, 1);
    assert.equal(out.kpis.missed.value, 1);
  });

  test('every day of the window is on the chart, including the empty ones', async () => {
    await seen(new Date('2026-09-10T10:00:00Z'));

    const out = await summary();
    assert.equal(out.perDay.length, 30);
    assert.equal(out.perDay[0].date, '2026-09-01');
    assert.equal(out.perDay[0].count, 0, 'a day nobody came is a gap, not a missing bar');
    assert.equal(out.perDay.find((d) => d.date === '2026-09-10').count, 1);
  });

  test('the comparison window is the same length, immediately before', async () => {
    const out = await summary();
    assert.deepEqual(out.previous, { from: '2026-08-02', to: '2026-08-31' });
  });
});

describe('what it will not make up', () => {
  test('no average until something has both ends of a consultation', async () => {
    await seen(new Date('2026-09-10T10:00:00Z'));

    const out = await summary();
    assert.equal(
      out.kpis.averageMinutes.value,
      null,
      'an appointment with no start and end is not a nought-minute consultation',
    );
    assert.equal(out.kpis.averageMinutes.from, 0);
  });

  test('the average says how many consultations it is made of', async () => {
    await seen(new Date('2026-09-10T10:00:00Z'), { minutes: 10 });
    await seen(new Date('2026-09-11T10:00:00Z'), { minutes: 20 });
    await seen(new Date('2026-09-12T10:00:00Z'));

    const out = await summary();
    assert.equal(out.kpis.averageMinutes.value, 15);
    assert.equal(out.kpis.averageMinutes.from, 2, 'the third had no times');
  });

  test('fees and referrals are absent, not zero', async () => {
    const out = await summary();
    // Nothing in this system records either. A zero would read as "nothing was
    // earned" and "nobody was referred", which are claims about the practice.
    assert.equal('fees' in out.kpis, false);
    assert.equal('referrals' in out, false);
  });
});

describe('the splits', () => {
  test('by location, with a consultation that had no room named as that', async () => {
    await seen(new Date('2026-09-10T10:00:00Z'), { clinic: salt });
    await seen(new Date('2026-09-11T10:00:00Z'), { clinic: salt });
    await seen(new Date('2026-09-12T10:00:00Z'));

    const out = await summary();
    assert.equal(out.byLocation[0].count, 2);
    assert.match(out.byLocation[0].name, /Salt Lake/);
    assert.equal(out.byLocation[1].name, 'No location recorded');
  });

  test('top diagnoses are counted off the prescriptions that carry them', async () => {
    const write = (diagnosis) =>
      Prescription.create({
        patient: patient._id,
        doctor: doctor._id,
        practice,
        referenceNo: `RX-${Math.random()}`,
        issuedOn: new Date('2026-09-10T10:00:00Z'),
        diagnosis,
      });
    await write(['Type 2 diabetes', 'Hypertension']);
    await write(['Type 2 diabetes']);
    await write(['Anaemia']);

    const out = await summary();
    assert.deepEqual(out.byDiagnosis[0], { name: 'Type 2 diabetes', count: 2 });
    assert.equal(out.kpis.prescriptions.value, 3);
  });
});

describe('the money, and the half of it the app cannot see', () => {
  async function charged(when, { amountPaise, status, paidPaise, apptStatus = 'completed' }) {
    return Appointment.create({
      patient: patient._id,
      doctor: doctor._id,
      practice,
      status: apptStatus,
      scheduledFor: when,
      fee: {
        amountPaise,
        status,
        ...(paidPaise == null ? {} : { paidPaise }),
      },
    });
  }

  test('nothing charged in the app reports nothing counted, not nothing earned', async () => {
    await seen(new Date('2026-09-10T10:00:00Z'));

    const out = await summary();
    assert.equal(out.fees.countedOf, 0);
    assert.equal(out.fees.collectedPaise, 0);
    assert.equal(
      out.fees.consultations,
      1,
      'the denominator is there so the screen can say 0 of 1 rather than ₹0',
    );
  });

  test('collected adds up what arrived; owed adds up what was asked', async () => {
    await charged(new Date('2026-09-10T10:00:00Z'), {
      amountPaise: 50000,
      status: 'paid',
      paidPaise: 50000,
    });
    await charged(new Date('2026-09-11T10:00:00Z'), {
      amountPaise: 30000,
      status: 'paid',
      paidPaise: 30000,
    });
    await charged(new Date('2026-09-12T10:00:00Z'), {
      amountPaise: 40000,
      status: 'pending',
    });

    const out = await summary();
    assert.equal(out.fees.collectedPaise, 80000);
    assert.equal(out.fees.paidCount, 2);
    assert.equal(out.fees.outstandingPaise, 40000);
    assert.equal(out.fees.outstandingCount, 1);
    assert.equal(out.fees.countedOf, 3);
  });

  test('a visit with no fee on it is not counted as a free one', async () => {
    await charged(new Date('2026-09-10T10:00:00Z'), {
      amountPaise: 50000,
      status: 'paid',
      paidPaise: 50000,
    });
    // A consultation the desk took cash for. It has no fee in the app, and
    // counting it would make the average fee look halved.
    await seen(new Date('2026-09-11T10:00:00Z'));

    const out = await summary();
    assert.equal(out.fees.countedOf, 1);
    assert.equal(out.fees.consultations, 2);
  });

  test('somebody who paid online and did not come has still paid', async () => {
    await charged(new Date('2026-09-10T10:00:00Z'), {
      amountPaise: 50000,
      status: 'paid',
      paidPaise: 50000,
      apptStatus: 'no_show',
    });

    const out = await summary();
    assert.equal(
      out.fees.collectedPaise,
      50000,
      'a month that dropped their money would not reconcile',
    );
  });

  test('the month before is there to compare against', async () => {
    await charged(new Date('2026-09-10T10:00:00Z'), {
      amountPaise: 50000,
      status: 'paid',
      paidPaise: 50000,
    });
    await charged(new Date('2026-08-10T10:00:00Z'), {
      amountPaise: 20000,
      status: 'paid',
      paidPaise: 20000,
    });

    const out = await summary();
    assert.equal(out.fees.collectedPaise, 50000);
    assert.equal(out.fees.previousCollectedPaise, 20000);
  });

  test('another practice’s takings are not in this one’s report', async () => {
    await Appointment.create({
      patient: patient._id,
      doctor: doctor._id,
      practice: other,
      status: 'completed',
      scheduledFor: new Date('2026-09-10T10:00:00Z'),
      fee: { amountPaise: 90000, status: 'paid', paidPaise: 90000 },
    });

    const out = await summary();
    assert.equal(out.fees.collectedPaise, 0);
  });
});
