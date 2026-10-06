import { test, describe, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { boot, shutdown, wipe, as } from './helpers/httpHarness.js';
import { makePractice, makeMember } from './helpers/factories.js';
import { Clinic } from '../src/models/Clinic.js';
import { Practice } from '../src/models/Practice.js';
import { Membership } from '../src/models/Membership.js';

/**
 * Which locations somebody may run, and what the plan is called.
 *
 * ---- Why these two, and nothing else --------------------------------------
 *
 * The People screen draws a tick box per location and a sentence that names
 * the plan, and neither had a field behind it. The list is the half that can
 * do harm: `locations` is read by `worksAt()` and by middleware/locationScope,
 * so a bad write here is a receptionist who can edit another branch's diary —
 * or one locked out of their own.
 *
 * So what is tested is the shape of the wall, not that an array round-trips:
 *
 *   · empty means every location, and must keep meaning that, because every
 *     membership written before the field existed has an empty list and all of
 *     those people run every branch this morning;
 *   · an id from another practice is refused rather than saved, since the
 *     scope would then honour a building this employer does not own;
 *   · an unknown id refuses the whole write rather than dropping one, because
 *     a half-saved list is a narrower wall than anybody asked for;
 *   · the denormalised `location` follows the list, so the roster cannot show
 *     Salt Lake for somebody narrowed to New Town.
 */

describe('the locations somebody may run', () => {
  before(boot);
  after(shutdown);
  beforeEach(wipe);

  async function clinic() {
    const practice = await makePractice('City Care');
    const head = await makeMember(practice, { name: 'Dr Sen', isOwner: true });
    const [saltLake, newTown] = await Promise.all([
      Clinic.create({ practice: practice._id, name: 'Salt Lake', isActive: true }),
      Clinic.create({ practice: practice._id, name: 'New Town', isActive: true }),
    ]);
    const desk = await makeMember(practice, { name: 'Tania Ghosh', role: 'staff' });
    return { practice, head, desk, saltLake, newTown };
  }

  test('every row that already exists narrows nobody', async () => {
    await clinic();

    // The state the whole reading rests on: an empty list is every location,
    // because this is what every membership written before the field holds.
    // If that ever stops being true, "empty means all" starts locking people
    // out of diaries they have run for a year.
    const rows = await Membership.find({}).lean();
    assert.ok(rows.length >= 2);
    for (const row of rows) {
      assert.deepEqual(row.locations ?? [], [], 'an existing row narrows nobody');
    }
  });

  test('narrowing somebody sends the list back with them', async () => {
    const { head, desk, saltLake } = await clinic();

    const res = await as(head.token).patch(`/team/${desk.membership._id}`, {
      locationIds: [String(saltLake._id)],
    });
    assert.equal(res.status, 200, JSON.stringify(res.body));

    const list = await as(head.token).get('/team');
    const row = list.body.items.find((i) => i.name === 'Tania Ghosh');
    assert.deepEqual(row.locationIds, [String(saltLake._id)]);
    // The default view followed the wall.
    assert.equal(row.location.id, String(saltLake._id));
    assert.equal(row.location.name, 'Salt Lake');
  });

  test('an empty list widens them back to every location', async () => {
    const { head, desk, saltLake } = await clinic();

    await as(head.token).patch(`/team/${desk.membership._id}`, {
      locationIds: [String(saltLake._id)],
    });
    const res = await as(head.token).patch(`/team/${desk.membership._id}`, {
      locationIds: [],
    });
    assert.equal(res.status, 200, JSON.stringify(res.body));

    const list = await as(head.token).get('/team');
    const row = list.body.items.find((i) => i.name === 'Tania Ghosh');
    assert.deepEqual(row.locationIds, []);
    // Nothing to be the default view of, so there is none — rather than the
    // last branch they happened to be narrowed to.
    assert.equal(row.location, null);
  });

  test('leaving the key out leaves the list alone', async () => {
    const { head, desk, saltLake, newTown } = await clinic();

    await as(head.token).patch(`/team/${desk.membership._id}`, {
      locationIds: [String(saltLake._id), String(newTown._id)],
    });
    const res = await as(head.token).patch(`/team/${desk.membership._id}`, {
      role: 'doctor_assistant',
    });
    assert.equal(res.status, 200, JSON.stringify(res.body));

    const row = await Membership.findById(desk.membership._id).lean();
    assert.equal(row.locations.length, 2, 'an older app must not clear the wall');
  });

  test('another practice’s clinic is refused, not saved', async () => {
    const { head, desk } = await clinic();
    const other = await Practice.create({ name: 'Elsewhere Clinic' });
    const theirs = await Clinic.create({
      practice: other._id,
      name: 'Behala',
      isActive: true,
    });

    const res = await as(head.token).patch(`/team/${desk.membership._id}`, {
      locationIds: [String(theirs._id)],
    });
    assert.equal(res.status, 404, JSON.stringify(res.body));

    const row = await Membership.findById(desk.membership._id).lean();
    assert.deepEqual(row.locations ?? [], [], 'nothing was written');
  });

  test('one unknown id refuses the whole list', async () => {
    const { head, desk, saltLake } = await clinic();

    const res = await as(head.token).patch(`/team/${desk.membership._id}`, {
      locationIds: [String(saltLake._id), '000000000000000000000000'],
    });
    assert.equal(res.status, 404, JSON.stringify(res.body));

    const row = await Membership.findById(desk.membership._id).lean();
    assert.deepEqual(
      row.locations ?? [],
      [],
      'a half-saved list is a narrower wall than anybody asked for',
    );
  });

  test('the roster names the plan, and sends null for a practice on none', async () => {
    const { practice, head } = await clinic();

    // A practice starts on the trial, so that is what the roster says it is
    // on — the key, which the app turns into the word.
    const started = await as(head.token).get('/team');
    assert.equal(started.status, 200);
    assert.equal(started.body.plan, 'trial');

    await Practice.findByIdAndUpdate(practice._id, {
      plan: 'professional',
      'limits.staff': 8,
    });
    const named = await as(head.token).get('/team');
    assert.equal(named.body.plan, 'professional');
    assert.equal(named.body.limits.staff, 8);

    // Null only where somebody has cleared it, which is the founding practice.
    await Practice.findByIdAndUpdate(practice._id, { $unset: { plan: 1 } });
    const none = await as(head.token).get('/team');
    assert.equal(none.body.plan, null, 'no plan is null, not a guessed tier');
  });

  test('the roster says when each job started', async () => {
    const { head } = await clinic();

    const res = await as(head.token).get('/team');
    const row = res.body.items.find((i) => i.name === 'Tania Ghosh');
    // The membership's own date. An account two years old that joined this
    // practice in March joined *here* in March.
    assert.ok(row.startedOn, 'a membership carries the day it started');
    assert.ok(!Number.isNaN(Date.parse(row.startedOn)));
  });
});
