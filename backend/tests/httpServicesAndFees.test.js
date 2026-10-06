import { test, describe, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { boot, shutdown, wipe, as, allText } from './helpers/httpHarness.js';
import { makePractice, makeMember, makePatient } from './helpers/factories.js';
import { ROLES } from '../src/models/User.js';
import { Service } from '../src/models/Service.js';
import { Appointment } from '../src/models/Appointment.js';
import { AuditLog } from '../src/models/AuditLog.js';

/**
 * The price list, over HTTP.
 *
 * ---- What is actually at stake -------------------------------------------
 *
 * A fee is the first thing in this app that a patient is asked to hand money
 * over for, so the questions worth asking of these routes are the money ones:
 * can one practice read or change another's prices, can anybody but the people
 * who run the business set them, does a price that has been booked against
 * survive being deleted, and does the amount on a booking come from the row
 * rather than from whatever the client typed.
 *
 * The payment half is tested where it can be: the order route is refused for
 * every reason it should be refused for. It is not driven through to a real
 * order, because that is a network call to Razorpay and the test harness
 * blocks outbound calls on purpose — see config/outbound.js.
 */

describe('the price list belongs to one practice', () => {
  before(boot);
  after(shutdown);
  beforeEach(wipe);

  test('a service is created and read back with its price in rupees too', async () => {
    const practice = await makePractice('Sunrise Diabetes Care');
    const owner = await makeMember(practice, { name: 'Dr Bose', isOwner: true });

    const made = await as(owner.token).post('/doctor/services', {
      name: 'Follow-up',
      mode: 'both',
      amountPaise: 49999,
      note: 'Within 14 days of your last visit',
    });
    assert.equal(made.status, 201);
    assert.equal(made.body.service.amountPaise, 49999);
    assert.equal(
      made.body.service.amountRupees,
      '499.99',
      'the screen must never do this division itself',
    );

    const list = await as(owner.token).get('/doctor/services');
    assert.equal(list.body.items.length, 1);
    assert.equal(list.body.items[0].name, 'Follow-up');
  });

  test('zero is a price the clinic set, and is stored as one', async () => {
    const practice = await makePractice('Sunrise Diabetes Care');
    const owner = await makeMember(practice, { name: 'Dr Bose', isOwner: true });

    const made = await as(owner.token).post('/doctor/services', {
      name: 'Follow-up within a fortnight',
      amountPaise: 0,
    });
    assert.equal(made.status, 201);
    assert.equal(made.body.service.amountPaise, 0);
    assert.equal(made.body.service.amountRupees, '0');
  });

  test('another practice’s prices are not readable or reachable by id', async () => {
    const sunrise = await makePractice('Sunrise Diabetes Care');
    const meridian = await makePractice('Meridian Family Clinic');
    const bose = await makeMember(sunrise, { name: 'Dr Bose', isOwner: true });
    const iyer = await makeMember(meridian, { name: 'Dr Iyer', isOwner: true });

    const theirs = await as(iyer.token).post('/doctor/services', {
      name: 'Meridian first visit',
      amountPaise: 90000,
    });
    assert.equal(theirs.status, 201);

    const mine = await as(bose.token).get('/doctor/services');
    assert.equal(mine.body.items.length, 0);
    assert.ok(
      !allText(mine.body).includes('Meridian first visit'),
      'another practice’s price list leaked',
    );

    const reach = await as(bose.token).patch(
      `/doctor/services/${theirs.body.service.id}`,
      { amountPaise: 100 },
    );
    assert.equal(reach.status, 404, 'scoped away, not quietly repriced');

    const stillTheirs = await Service.findById(theirs.body.service.id).lean();
    assert.equal(stillTheirs.amountPaise, 90000);
  });

  test('a doctor without MANAGE_STAFF may read the list and not set it', async () => {
    const practice = await makePractice('Sunrise Diabetes Care');
    const owner = await makeMember(practice, { name: 'Dr Bose', isOwner: true });
    // A locum: prescribing rights, no say in what the clinic charges.
    const locum = await makeMember(practice, {
      name: 'Dr Rao',
      permissions: ['VIEW_PATIENT', 'PRESCRIBE'],
    });

    await as(owner.token).post('/doctor/services', {
      name: 'Follow-up',
      amountPaise: 30000,
    });

    const read = await as(locum.token).get('/doctor/services');
    assert.equal(read.status, 200, 'a doctor about to book needs to know the price');
    assert.equal(read.body.items.length, 1);

    const write = await as(locum.token).post('/doctor/services', {
      name: 'Rao’s own rate',
      amountPaise: 1,
    });
    assert.equal(write.status, 403);
  });

  test('the front desk is not a clinician and gets nowhere near it', async () => {
    const practice = await makePractice('Sunrise Diabetes Care');
    const desk = await makeMember(practice, { name: 'Sunita Desk', role: ROLES.STAFF });

    const read = await as(desk.token).get('/doctor/services');
    assert.ok(read.status === 403 || read.status === 401, `got ${read.status}`);
  });

  test('two services cannot share a name, and the second is told why', async () => {
    const practice = await makePractice('Sunrise Diabetes Care');
    const owner = await makeMember(practice, { name: 'Dr Bose', isOwner: true });

    await as(owner.token).post('/doctor/services', {
      name: 'Follow-up',
      amountPaise: 30000,
    });
    const again = await as(owner.token).post('/doctor/services', {
      name: 'Follow-up',
      amountPaise: 40000,
    });
    assert.equal(again.status, 409);
    assert.match(again.body.error?.message ?? '', /already a service with that name/i);
  });

  test('a price change records both sides of it', async () => {
    const practice = await makePractice('Sunrise Diabetes Care');
    const owner = await makeMember(practice, { name: 'Dr Bose', isOwner: true });

    const made = await as(owner.token).post('/doctor/services', {
      name: 'Follow-up',
      amountPaise: 30000,
    });
    await as(owner.token).patch(`/doctor/services/${made.body.service.id}`, {
      amountPaise: 45000,
    });

    // The route answers before the row is written; the write is fire-and-
    // forget by design so a logging failure cannot fail a request.
    await new Promise((r) => setTimeout(r, 120));
    const rows = await AuditLog.find({ resource: 'Service', action: 'update' }).lean();
    assert.equal(rows.length, 1);
    assert.equal(
      rows[0].meta.before.amountPaise,
      30000,
      '"who raised the fee, and from what" is the question this answers',
    );
    assert.equal(rows[0].meta.after.amountPaise, 45000);
  });
});

describe('a service that has been booked against', () => {
  before(boot);
  after(shutdown);
  beforeEach(wipe);

  test('is withdrawn rather than deleted, and says so', async () => {
    const practice = await makePractice('Sunrise Diabetes Care');
    const owner = await makeMember(practice, { name: 'Dr Bose', isOwner: true });
    const patient = await makePatient({ name: 'Anita Sengupta', practices: [practice] });

    const made = await as(owner.token).post('/doctor/services', {
      name: 'Follow-up',
      amountPaise: 30000,
    });
    await Appointment.create({
      patient: patient.user._id,
      doctor: owner.user._id,
      practice: practice._id,
      status: 'completed',
      scheduledFor: new Date(),
      service: made.body.service.id,
      fee: { amountPaise: 30000, status: 'paid', paidPaise: 30000 },
    });

    const gone = await as(owner.token).del(`/doctor/services/${made.body.service.id}`);
    assert.equal(gone.status, 200);
    assert.equal(gone.body.withdrawn, true);
    assert.match(gone.body.message, /withdrawn rather than deleted/i);

    const row = await Service.findById(made.body.service.id).lean();
    assert.ok(row, 'the row a receipt reads from must survive');
    assert.equal(row.isActive, false);
  });

  test('and one nobody booked is removed outright', async () => {
    const practice = await makePractice('Sunrise Diabetes Care');
    const owner = await makeMember(practice, { name: 'Dr Bose', isOwner: true });

    const made = await as(owner.token).post('/doctor/services', {
      name: 'Never used',
      amountPaise: 10000,
    });
    const gone = await as(owner.token).del(`/doctor/services/${made.body.service.id}`);
    assert.equal(gone.body.deleted, true);
    assert.equal(await Service.countDocuments({}), 0);
  });

  test('a withdrawn service is off the list the booking screen reads', async () => {
    const practice = await makePractice('Sunrise Diabetes Care');
    const owner = await makeMember(practice, { name: 'Dr Bose', isOwner: true });

    const made = await as(owner.token).post('/doctor/services', {
      name: 'Follow-up',
      amountPaise: 30000,
    });
    await as(owner.token).patch(`/doctor/services/${made.body.service.id}`, {
      isActive: false,
    });

    const offered = await as(owner.token).get('/doctor/services');
    assert.equal(offered.body.items.length, 0, 'a patient would turn up for it');

    const editing = await as(owner.token).get('/doctor/services?includeWithdrawn=1');
    assert.equal(editing.body.items.length, 1, 'whoever edits the list still sees it');
  });
});

describe('what a booking is charged', () => {
  before(boot);
  after(shutdown);
  beforeEach(wipe);

  /** A practice with one doctor, one patient and one priced service. */
  async function clinic({ amountPaise = 50000, mode = 'both' } = {}) {
    const practice = await makePractice('Sunrise Diabetes Care');
    const owner = await makeMember(practice, { name: 'Dr Bose', isOwner: true });
    const patient = await makePatient({
      name: 'Anita Sengupta',
      practices: [practice],
      primaryDoctor: owner.user,
    });
    const service = await Service.create({
      practice: practice._id,
      name: 'New consultation',
      amountPaise,
      mode,
    });
    return { practice, owner, patient, service };
  }

  function tomorrowAt(hour) {
    const d = new Date();
    d.setDate(d.getDate() + 1);
    d.setHours(hour, 0, 0, 0);
    return d;
  }

  test('the amount comes from the row, never from the request', async () => {
    const { owner, patient, service } = await clinic({ amountPaise: 50000 });

    const booked = await as(owner.token).post('/appointments', {
      patientId: String(patient.user._id),
      scheduledFor: tomorrowAt(10).toISOString(),
      serviceId: String(service._id),
      // A client naming its own price. It is not a field, and the point of
      // sending it is to prove that it is not read.
      amountPaise: 1,
      fee: { amountPaise: 1, status: 'paid' },
    });
    assert.equal(booked.status, 201, JSON.stringify(booked.body));
    assert.equal(booked.body.appointment.fee.amountPaise, 50000);
    assert.equal(booked.body.appointment.fee.status, 'pending');

    const row = await Appointment.findById(booked.body.appointment.id).lean();
    assert.equal(row.fee.paidPaise, null, 'nothing is paid by asking for it to be');
  });

  test('a booking with no service owes nothing through the app', async () => {
    const { owner, patient } = await clinic();

    const booked = await as(owner.token).post('/appointments', {
      patientId: String(patient.user._id),
      scheduledFor: tomorrowAt(11).toISOString(),
    });
    assert.equal(booked.status, 201);
    assert.equal(booked.body.appointment.fee.status, 'not_required');
    assert.equal(
      booked.body.appointment.fee.amountPaise,
      null,
      'null, because the desk is about to ask for cash — that is not free',
    );
  });

  test('a free service is booked as owing nothing, not as awaiting payment', async () => {
    const { owner, patient, service } = await clinic({ amountPaise: 0 });

    const booked = await as(owner.token).post('/appointments', {
      patientId: String(patient.user._id),
      scheduledFor: tomorrowAt(12).toISOString(),
      serviceId: String(service._id),
    });
    assert.equal(booked.body.appointment.fee.amountPaise, 0);
    assert.equal(booked.body.appointment.fee.status, 'not_required');
  });

  test('another practice’s service cannot be booked against', async () => {
    const { owner, patient } = await clinic();
    const elsewhere = await makePractice('Meridian Family Clinic');
    const theirs = await Service.create({
      practice: elsewhere._id,
      name: 'Meridian rate',
      amountPaise: 10,
    });

    const booked = await as(owner.token).post('/appointments', {
      patientId: String(patient.user._id),
      scheduledFor: tomorrowAt(13).toISOString(),
      serviceId: String(theirs._id),
    });
    assert.equal(booked.status, 400);
    assert.match(booked.body.error?.message ?? '', /not available/i);
  });

  test('a withdrawn service cannot be booked against', async () => {
    const { owner, patient, service } = await clinic();
    service.isActive = false;
    await service.save();

    const booked = await as(owner.token).post('/appointments', {
      patientId: String(patient.user._id),
      scheduledFor: tomorrowAt(14).toISOString(),
      serviceId: String(service._id),
    });
    assert.equal(booked.status, 400);
  });

  test('a clinic-only service is refused for a video call, not quietly repriced', async () => {
    const { owner, patient, service } = await clinic({ mode: 'in_clinic' });

    const booked = await as(owner.token).post('/appointments', {
      patientId: String(patient.user._id),
      scheduledFor: tomorrowAt(15).toISOString(),
      mode: 'teleconsult',
      serviceId: String(service._id),
    });
    assert.equal(booked.status, 400);
    assert.match(booked.body.error?.message ?? '', /not offered for this kind of visit/i);
  });
});

describe('starting a payment', () => {
  before(boot);
  after(shutdown);
  beforeEach(wipe);

  async function booking(fee) {
    const practice = await makePractice('Sunrise Diabetes Care');
    const owner = await makeMember(practice, { name: 'Dr Bose', isOwner: true });
    const patient = await makePatient({ name: 'Anita Sengupta', practices: [practice] });
    const appointment = await Appointment.create({
      patient: patient.user._id,
      doctor: owner.user._id,
      practice: practice._id,
      status: 'confirmed',
      scheduledFor: new Date(Date.now() + 86_400_000),
      fee,
    });
    return { owner, patient, appointment };
  }

  test('is refused where nothing is owed through the app', async () => {
    const { owner, appointment } = await booking({ status: 'not_required' });

    const res = await as(owner.token).post(`/appointments/${appointment._id}/fee/order`);
    assert.equal(res.status, 400);
    assert.match(res.body.error?.message ?? '', /nothing is owed/i);
  });

  test('is refused on something already paid', async () => {
    const { owner, appointment } = await booking({
      amountPaise: 50000,
      status: 'paid',
      paidPaise: 50000,
    });

    const res = await as(owner.token).post(`/appointments/${appointment._id}/fee/order`);
    assert.equal(res.status, 400);
    assert.match(res.body.error?.message ?? '', /already been paid/i);
  });

  test('is refused on somebody else’s appointment', async () => {
    const { appointment } = await booking({ amountPaise: 50000, status: 'pending' });
    const elsewhere = await makePractice('Meridian Family Clinic');
    const iyer = await makeMember(elsewhere, { name: 'Dr Iyer', isOwner: true });

    const res = await as(iyer.token).post(`/appointments/${appointment._id}/fee/order`);
    assert.equal(res.status, 404, 'scoped away by id, as every other route here is');
  });

  test('confirming one with no order started is refused', async () => {
    const { owner, appointment } = await booking({ amountPaise: 50000, status: 'pending' });

    const res = await as(owner.token).post(
      `/appointments/${appointment._id}/fee/verify`,
      { paymentId: 'pay_made_up', signature: 'x'.repeat(64) },
    );
    assert.equal(res.status, 400);
    assert.match(res.body.error?.message ?? '', /no payment has been started/i);
  });

  test('an unsigned payment moves nothing, however confident the caller', async () => {
    const { owner, appointment } = await booking({
      amountPaise: 50000,
      status: 'pending',
      orderId: 'order_FORGED',
    });

    const res = await as(owner.token).post(
      `/appointments/${appointment._id}/fee/verify`,
      { paymentId: 'pay_FORGED', signature: 'f'.repeat(64) },
    );
    assert.equal(res.status, 400);
    assert.match(res.body.error?.message ?? '', /could not be verified/i);

    const row = await Appointment.findById(appointment._id).lean();
    assert.equal(row.fee.status, 'pending', 'a forged signature paid for a visit');
    assert.equal(row.fee.paidAt, null);
  });

  test('a payment claimed for a different order is refused, not ignored', async () => {
    const { owner, appointment } = await booking({
      amountPaise: 50000,
      status: 'pending',
      orderId: 'order_OURS',
    });

    const res = await as(owner.token).post(
      `/appointments/${appointment._id}/fee/verify`,
      {
        paymentId: 'pay_X',
        signature: 's'.repeat(64),
        orderId: 'order_SOMEBODY_ELSES',
      },
    );
    assert.equal(res.status, 400);
    assert.match(res.body.error?.message ?? '', /different order/i);
  });
});

describe('the fees register', () => {
  before(boot);
  after(shutdown);
  beforeEach(wipe);

  async function clinic() {
    const practice = await makePractice('Sunrise Diabetes Care');
    const owner = await makeMember(practice, { name: 'Dr Bose', isOwner: true });
    const patient = await makePatient({ name: 'Anita Sengupta', practices: [practice] });
    const service = await Service.create({
      practice: practice._id,
      name: 'New consultation',
      amountPaise: 50000,
    });
    return { practice, owner, patient, service };
  }

  const window_ = '?from=2026-09-01&to=2026-09-30';

  test('lists what was charged, paid and unpaid alike', async () => {
    const { practice, owner, patient, service } = await clinic();
    await Appointment.create({
      patient: patient.user._id,
      doctor: owner.user._id,
      practice: practice._id,
      status: 'completed',
      scheduledFor: new Date('2026-09-10T10:00:00Z'),
      service: service._id,
      fee: { amountPaise: 50000, status: 'paid', paidPaise: 50000, paidAt: new Date() },
    });
    await Appointment.create({
      patient: patient.user._id,
      doctor: owner.user._id,
      practice: practice._id,
      status: 'confirmed',
      scheduledFor: new Date('2026-09-12T10:00:00Z'),
      service: service._id,
      fee: { amountPaise: 30000, status: 'pending' },
    });

    const res = await as(owner.token).get('/doctor/reports/fees' + window_);
    assert.equal(res.status, 200);
    assert.equal(res.body.items.length, 2, 'who still owes is why this list is opened');
    assert.equal(res.body.items[0].feeStatus, 'pending', 'newest first');
    assert.equal(res.body.items[1].paidPaise, 50000);
    assert.equal(res.body.items[1].serviceName, 'New consultation');
  });

  test('leaves out the visits the app did not charge for', async () => {
    const { practice, owner, patient } = await clinic();
    await Appointment.create({
      patient: patient.user._id,
      doctor: owner.user._id,
      practice: practice._id,
      status: 'completed',
      scheduledFor: new Date('2026-09-10T10:00:00Z'),
    });

    const res = await as(owner.token).get('/doctor/reports/fees' + window_);
    assert.equal(
      res.body.items.length,
      0,
      'a cash visit is not a ₹0 line in a payments register',
    );
  });

  test('somebody who paid and did not come is still in it, and says so', async () => {
    const { practice, owner, patient, service } = await clinic();
    await Appointment.create({
      patient: patient.user._id,
      doctor: owner.user._id,
      practice: practice._id,
      status: 'no_show',
      scheduledFor: new Date('2026-09-10T10:00:00Z'),
      service: service._id,
      fee: { amountPaise: 50000, status: 'paid', paidPaise: 50000 },
    });

    const res = await as(owner.token).get('/doctor/reports/fees' + window_);
    assert.equal(res.body.items.length, 1);
    assert.equal(res.body.items[0].visitStatus, 'no_show');
    assert.equal(res.body.items[0].paidPaise, 50000);
  });

  test('another practice’s money is not in it', async () => {
    const { owner } = await clinic();
    const elsewhere = await makePractice('Meridian Family Clinic');
    const iyer = await makeMember(elsewhere, { name: 'Dr Iyer', isOwner: true });
    const theirPatient = await makePatient({
      name: 'Farida Rahman',
      practices: [elsewhere],
    });
    await Appointment.create({
      patient: theirPatient.user._id,
      doctor: iyer.user._id,
      practice: elsewhere._id,
      status: 'completed',
      scheduledFor: new Date('2026-09-10T10:00:00Z'),
      fee: { amountPaise: 90000, status: 'paid', paidPaise: 90000 },
    });

    const res = await as(owner.token).get('/doctor/reports/fees' + window_);
    assert.equal(res.body.items.length, 0);
    assert.ok(!allText(res.body).includes('Farida Rahman'));
  });
});
