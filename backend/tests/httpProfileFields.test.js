import { test, describe, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { boot, shutdown, wipe, as } from './helpers/httpHarness.js';
import { makePractice, makeMember } from './helpers/factories.js';
import { Clinic } from '../src/models/Clinic.js';
import { Practice } from '../src/models/Practice.js';
import { User } from '../src/models/User.js';

/**
 * The profile fields the design asks for, now that they exist.
 *
 * ---- What is worth testing here -------------------------------------------
 *
 * Not that a string round-trips. Three things: that a field somebody filled in
 * by mistake can be *cleared* — `.optional()` alone only lets a caller leave it
 * alone, which is a profile nobody can correct; that leaving a key out changes
 * nothing, because an older app that saves hours must not reset the slot rules
 * it has never heard of; and that a window of no time is refused, because a
 * message thread that silently accepts nothing is a clinic its patients think
 * has stopped answering.
 *
 * And one thing that must stay absent: a verified mark. Nothing here calls
 * ABDM, so an HPR id is a number somebody typed.
 */

describe('the doctor’s professional profile', () => {
  before(boot);
  after(shutdown);
  beforeEach(wipe);

  async function doctor() {
    const practice = await makePractice('Sunrise Diabetes Care');
    return makeMember(practice, { name: 'Dr Bose', isOwner: true });
  }

  test('the structured fields save and come back whole', async () => {
    const bose = await doctor();

    const res = await as(bose.token).patch('/auth/me', {
      professionType: 'doctor',
      council: 'West Bengal Medical Council',
      registrationYear: 2008,
      hprId: 'HPR-1234',
      degrees: [
        { name: 'MBBS', institution: 'Calcutta Medical College', year: 2008 },
        { name: 'MD, Internal Medicine', institution: 'IPGMER', year: 2012 },
      ],
      specialisations: ['Diabetology', 'Internal medicine'],
      conditionsTreated: ['Type 2 diabetes', 'Hypertension'],
      practisingSince: 2010,
      memberships: ['RSSDI member'],
      bio: 'Diabetes and heart care since 2011.',
      languages: ['en', 'bn'],
    });
    assert.equal(res.status, 200, JSON.stringify(res.body));

    const me = res.body.user;
    assert.equal(me.professionType, 'doctor');
    assert.equal(me.council, 'West Bengal Medical Council');
    assert.equal(me.registrationYear, 2008);
    assert.equal(me.degrees.length, 2);
    assert.equal(me.degrees[0].institution, 'Calcutta Medical College');
    assert.deepEqual(me.specialisations, ['Diabetology', 'Internal medicine']);
    assert.deepEqual(me.conditionsTreated, ['Type 2 diabetes', 'Hypertension']);
    assert.equal(me.practisingSince, 2010);
    assert.deepEqual(me.memberships, ['RSSDI member']);
    assert.deepEqual(me.languages, ['en', 'bn']);
  });

  test('an HPR id is stored and never comes back verified', async () => {
    const bose = await doctor();
    const res = await as(bose.token).patch('/auth/me', { hprId: 'HPR-1234' });

    assert.equal(res.body.user.hprId, 'HPR-1234');
    assert.ok(
      !Object.keys(res.body.user).some((k) => /verif/i.test(k)),
      'nothing here asks ABDM, so nothing may claim a verification',
    );
  });

  test('a field filled in by mistake can be cleared', async () => {
    const bose = await doctor();
    await as(bose.token).patch('/auth/me', { council: 'Wrong Council' });

    const res = await as(bose.token).patch('/auth/me', { council: null });
    assert.equal(res.status, 200);
    assert.equal(res.body.user.council, null);
  });

  test('a degree with no name is refused, not stored blank', async () => {
    const bose = await doctor();
    const res = await as(bose.token).patch('/auth/me', {
      degrees: [{ institution: 'IPGMER', year: 2012 }],
    });
    assert.equal(res.status, 400);
  });

  test('a year before medicine is refused', async () => {
    const bose = await doctor();
    const res = await as(bose.token).patch('/auth/me', { practisingSince: 1200 });
    assert.equal(res.status, 400);
  });

  test('the arrays come back as arrays on a profile nobody has filled in', async () => {
    const bose = await doctor();
    const res = await as(bose.token).get('/auth/me');
    const me = res.body.user;
    assert.deepEqual(me.degrees, []);
    assert.deepEqual(me.specialisations, []);
    assert.deepEqual(me.conditionsTreated, []);
    assert.deepEqual(me.memberships, []);
    assert.deepEqual(me.languages, []);
    assert.equal(me.bio, null);
  });
});

describe('what a location is, and what it takes', () => {
  before(boot);
  after(shutdown);
  beforeEach(wipe);

  async function room() {
    const practice = await makePractice('Sunrise Diabetes Care');
    const bose = await makeMember(practice, { name: 'Dr Bose', isOwner: true });
    const clinic = await Clinic.create({
      name: 'Sunrise Salt Lake',
      practice: practice._id,
    });
    return { bose, clinic };
  }

  test('the new fields save and come back', async () => {
    const { bose, clinic } = await room();

    const res = await as(bose.token).patch(`/clinics/${clinic._id}`, {
      kind: 'diagnostic_centre',
      landmark: 'Opposite Tank 9',
      hfrId: 'HFR-99',
      facilities: ['Wheelchair access', 'Parking'],
      paymentMethods: ['upi', 'cash'],
      collectFeeAtBooking: true,
    });
    assert.equal(res.status, 200, JSON.stringify(res.body));

    const saved = await Clinic.findById(clinic._id).lean();
    assert.equal(saved.kind, 'diagnostic_centre');
    assert.equal(saved.landmark, 'Opposite Tank 9');
    assert.equal(saved.hfrId, 'HFR-99');
    assert.deepEqual(saved.facilities, ['Wheelchair access', 'Parking']);
    assert.deepEqual(saved.paymentMethods, ['upi', 'cash']);
    assert.equal(saved.collectFeeAtBooking, true);
  });

  test('a payment method nobody takes is refused', async () => {
    const { bose, clinic } = await room();
    const res = await as(bose.token).patch(`/clinics/${clinic._id}`, {
      paymentMethods: ['bitcoin'],
    });
    assert.equal(res.status, 400);
  });

  test('a location that predates the fields reads as a clinic taking nothing', async () => {
    const { bose, clinic } = await room();
    const res = await as(bose.token).get(`/clinics/${clinic._id}`);
    const body = res.body.clinic ?? res.body;
    assert.equal(body.kind, 'clinic');
    assert.deepEqual(body.facilities, []);
    assert.deepEqual(body.paymentMethods, []);
    assert.equal(body.collectFeeAtBooking, false);
  });
});

describe('how a sitting is cut up', () => {
  before(boot);
  after(shutdown);
  beforeEach(wipe);

  async function room() {
    const practice = await makePractice('Sunrise Diabetes Care');
    const bose = await makeMember(practice, { name: 'Dr Bose', isOwner: true });
    const clinic = await Clinic.create({
      name: 'Sunrise Salt Lake',
      practice: practice._id,
    });
    return { bose, clinic };
  }

  const hours = [{ dayOfWeek: 1, start: '09:00', end: '13:00' }];

  test('the slot rules save beside the hours', async () => {
    const { bose, clinic } = await room();

    const res = await as(bose.token).put(
      `/clinics/${clinic._id}/availability/${bose.user._id}`,
      {
        slotMinutes: 15,
        weeklyHours: hours,
        patientsPerSlot: 2,
        walkInPlaces: 4,
        breakMinutes: 5,
      },
    );
    assert.equal(res.status, 200, JSON.stringify(res.body));

    const { Availability } = await import('../src/models/Availability.js');
    const saved = await Availability.findOne({
      doctor: bose.user._id,
      location: clinic._id,
    }).lean();
    assert.equal(saved.patientsPerSlot, 2);
    assert.equal(saved.walkInPlaces, 4);
    assert.equal(saved.breakMinutes, 5);
  });

  test('saving only the hours leaves the rules it has never heard of alone', async () => {
    const { bose, clinic } = await room();
    const url = `/clinics/${clinic._id}/availability/${bose.user._id}`;

    await as(bose.token).put(url, {
      slotMinutes: 15,
      weeklyHours: hours,
      walkInPlaces: 4,
    });
    // An older app, saving hours and nothing else.
    await as(bose.token).put(url, { slotMinutes: 20, weeklyHours: hours });

    const { Availability } = await import('../src/models/Availability.js');
    const saved = await Availability.findOne({
      doctor: bose.user._id,
      location: clinic._id,
    }).lean();
    assert.equal(saved.slotMinutes, 20, 'what it did send');
    assert.equal(
      saved.walkInPlaces,
      4,
      'a key left out is a setting not touched, not one cleared',
    );
  });

  test('more walk-in places than a session has is refused', async () => {
    const { bose, clinic } = await room();
    const res = await as(bose.token).put(
      `/clinics/${clinic._id}/availability/${bose.user._id}`,
      { slotMinutes: 15, weeklyHours: hours, walkInPlaces: 500 },
    );
    assert.equal(res.status, 400);
  });
});

describe('the rules a patient meets', () => {
  before(boot);
  after(shutdown);
  beforeEach(wipe);

  async function owner() {
    const practice = await makePractice('Sunrise Diabetes Care');
    const bose = await makeMember(practice, { name: 'Dr Bose', isOwner: true });
    return { practice, bose };
  }

  test('a practice that has never opened the screen behaves as it does today', async () => {
    // There is no GET /practices/:id — the app reads its own practice.
    const { bose } = await owner();
    const res = await as(bose.token).get('/practices/mine');
    const body = res.body.practice ?? res.body;

    assert.equal(body.booking.online, true, 'booking is open until somebody closes it');
    assert.equal(body.booking.windowDays, null, 'no limit');
    assert.equal(body.booking.cancelCutoffHours, null, 'cancel any time');
    assert.equal(body.followUpReminder.daysBefore, 3);
    assert.deepEqual(body.followUpReminder.channels, ['app']);
    assert.equal(body.patientMessaging.always, true);
    assert.equal(body.patientMessaging.urgentAlways, true);
  });

  test('they save', async () => {
    const { practice, bose } = await owner();

    const res = await as(bose.token).patch(`/practices/${practice._id}`, {
      booking: { online: false, windowDays: 7, cancelCutoffHours: 4 },
      followUpReminder: { daysBefore: 2, channels: ['app', 'whatsapp'] },
      patientMessaging: {
        always: false,
        from: '09:00',
        to: '18:00',
        urgentAlways: true,
      },
    });
    assert.equal(res.status, 200, JSON.stringify(res.body));

    const saved = await Practice.findById(practice._id).lean();
    assert.equal(saved.booking.online, false);
    assert.equal(saved.booking.windowDays, 7);
    assert.equal(saved.followUpReminder.daysBefore, 2);
    assert.equal(saved.patientMessaging.from, '09:00');
  });

  test('a messaging window of no time is refused', async () => {
    const { practice, bose } = await owner();
    const res = await as(bose.token).patch(`/practices/${practice._id}`, {
      patientMessaging: {
        always: false,
        from: '09:00',
        to: '09:00',
        urgentAlways: true,
      },
    });
    assert.equal(res.status, 400);
    assert.match(res.body.error?.message ?? '', /real window/i);
  });

  test('closed hours with no hours given is refused', async () => {
    const { practice, bose } = await owner();
    const res = await as(bose.token).patch(`/practices/${practice._id}`, {
      patientMessaging: { always: false, from: null, to: null, urgentAlways: true },
    });
    assert.equal(res.status, 400);
  });

  test('a doctor without MANAGE_STAFF cannot set them', async () => {
    const { practice } = await owner();
    const locum = await makeMember(practice, {
      name: 'Dr Rao',
      permissions: ['VIEW_PATIENT', 'PRESCRIBE'],
    });

    const res = await as(locum.token).patch(`/practices/${practice._id}`, {
      booking: { online: false, windowDays: null, cancelCutoffHours: null },
    });
    assert.equal(res.status, 403);
  });

  test('another practice’s rules are not reachable', async () => {
    const { bose } = await owner();
    const elsewhere = await makePractice('Meridian Family Clinic');
    await makeMember(elsewhere, { name: 'Dr Iyer', isOwner: true });

    const res = await as(bose.token).patch(`/practices/${elsewhere._id}`, {
      booking: { online: false, windowDays: null, cancelCutoffHours: null },
    });
    assert.ok(res.status === 403 || res.status === 404, `got ${res.status}`);

    const saved = await Practice.findById(elsewhere._id).lean();
    assert.notEqual(saved.booking?.online, false);
  });
});

describe('the user model keeps what prints separate from what is searched', () => {
  before(boot);
  after(shutdown);
  beforeEach(wipe);

  test('the printed line is not rebuilt from the degrees', async () => {
    // A doctor who wants "MBBS, MD (Medicine)" on their prescription is not
    // served by it being assembled from rows.
    const practice = await makePractice('Sunrise Diabetes Care');
    const bose = await makeMember(practice, { name: 'Dr Bose', isOwner: true });

    await as(bose.token).patch('/auth/me', {
      qualifications: 'MBBS, MD (Medicine)',
      degrees: [{ name: 'MBBS' }, { name: 'MD' }],
    });

    const saved = await User.findById(bose.user._id).lean();
    assert.equal(saved.qualifications, 'MBBS, MD (Medicine)');
    assert.equal(saved.degrees.length, 2);
  });
});
