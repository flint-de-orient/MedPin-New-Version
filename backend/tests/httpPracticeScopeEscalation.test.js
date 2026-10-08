import { test, describe, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { boot, shutdown, wipe, as } from './helpers/httpHarness.js';
import { makePractice, makeMember } from './helpers/factories.js';
import { Practice } from '../src/models/Practice.js';
import { Membership } from '../src/models/Membership.js';

/**
 * The practice a request names, and the practice its permission came from,
 * have to be the same one.
 *
 * ---- The escalation this pins shut ---------------------------------------
 *
 * `requirePermission(MANAGE_STAFF)` resolves the membership it tests through
 * `practiceOf(req)` — the `x-medpin-practice` header. Every route in
 * routes/practices.js takes its practice from the URL instead, and
 * `assertBelongs` only asked "are you a member here". Nothing compared them.
 *
 * So an owner of practice A who is also a plain member of practice B could
 * send the A header with a B url and rewrite B's prescription letterhead —
 * the name and registration number that print on a legal document — and
 * redirect B's payout bank account.
 *
 * Reachable with a token and curl rather than from the app, which sends no
 * practice header at all. That makes it quiet, not small.
 */

describe('a practice in the url is checked against the one in scope', () => {
  before(boot);
  after(shutdown);
  beforeEach(wipe);

  /**
   * One person, two practices: head of their own, ordinary doctor at the
   * other. The ordinary-doctor preset holds no MANAGE_STAFF.
   */
  async function twoPractices() {
    const mine = await makePractice('Sunrise Diabetes Care');
    const theirs = await makePractice('City Care');

    const me = await makeMember(mine, { name: 'Dr Bose', isOwner: true });
    await Membership.create({
      user: me.user._id,
      practice: theirs._id,
      role: 'doctor',
      isOwner: false,
      status: 'active',
      startedOn: new Date(),
      endedOn: null,
    });

    return { mine, theirs, me };
  }

  /** The header `practiceOf` reads — third argument on every verb. */
  const scope = (practiceId) => ({ 'x-medpin-practice': String(practiceId) });

  test('the other practice’s letterhead cannot be rewritten from mine', async () => {
    const { mine, theirs, me } = await twoPractices();

    const res = await as(me.token).patch(
      `/practices/${theirs._id}`,
      { name: 'Renamed By Somebody Else', registrationNo: 'NOT-THEIRS' },
      scope(mine._id),
    );
    assert.ok(res.status === 403 || res.status === 404, `got ${res.status}`);

    const after = await Practice.findById(theirs._id).lean();
    assert.equal(after.name, 'City Care', 'the name was rewritten');
    assert.ok(!after.registrationNo, 'a registration number was written');
  });

  test('the other practice’s payout account cannot be redirected', async () => {
    const { mine, theirs, me } = await twoPractices();

    const res = await as(me.token).patch(
      `/practices/${theirs._id}`,
      {
        payout: {
          accountName: 'Somebody Else',
          accountNumber: '50100111222333',
          ifsc: 'HDFC0001234',
          bankName: null,
          upiId: null,
        },
      },
      scope(mine._id),
    );
    assert.ok(res.status === 403 || res.status === 404, `got ${res.status}`);

    const after = await Practice.findById(theirs._id).lean();
    assert.ok(!after.payout?.accountLast4, 'a bank account was written');
  });

  test('nobody can be added to the other practice from mine', async () => {
    const { mine, theirs, me } = await twoPractices();

    const res = await as(me.token).post(
      `/practices/${theirs._id}/members`,
      {
        // A body that passes validation, so what refuses is the guard and
        // not the schema. The token is nonsense and would be refused a line
        // later — assertOwner has to get there first.
        role: 'doctor',
        name: 'Planted',
        phone: '+919830011223',
        phoneToken: 'x'.repeat(24),
      },
      scope(mine._id),
    );
    assert.ok(res.status === 403 || res.status === 404, `got ${res.status}`);
  });

  test('my own practice still works, named or not', async () => {
    const { mine, me } = await twoPractices();

    const named = await as(me.token).patch(
      `/practices/${mine._id}`,
      { tagline: 'Diabetes and heart care' },
      scope(mine._id),
    );
    assert.equal(named.status, 200, JSON.stringify(named.body));
    assert.equal(named.body.practice.tagline, 'Diabetes and heart care');
  });

  test('a single-practice owner is unaffected and needs no header', async () => {
    const practice = await makePractice('Solo Clinic');
    const head = await makeMember(practice, { name: 'Dr Sen', isOwner: true });

    const res = await as(head.token).patch(`/practices/${practice._id}`, {
      tagline: 'One doctor, one clinic',
    });
    assert.equal(res.status, 200, JSON.stringify(res.body));
  });
});

describe('/practices/mine resolves one practice, never the first row', () => {
  before(boot);
  after(shutdown);
  beforeEach(wipe);

  test('a single practice comes back without a header', async () => {
    const practice = await makePractice('Solo Clinic');
    const head = await makeMember(practice, { name: 'Dr Sen', isOwner: true });

    const res = await as(head.token).get('/practices/mine');
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.practice.name, 'Solo Clinic');
  });

  test('two practices and no header is refused, not guessed', async () => {
    const a = await makePractice('Sunrise');
    const b = await makePractice('City Care');
    const me = await makeMember(a, { name: 'Dr Bose', isOwner: true });
    await Membership.create({
      user: me.user._id,
      practice: b._id,
      role: 'doctor',
      status: 'active',
      startedOn: new Date(),
      endedOn: null,
    });

    const res = await as(me.token).get('/practices/mine');
    assert.equal(res.status, 409, JSON.stringify(res.body));
    assert.equal(res.body.error.code, 'PRACTICE_REQUIRED');
  });

  test('two practices and a header gives the one named', async () => {
    const a = await makePractice('Sunrise');
    const b = await makePractice('City Care');
    const me = await makeMember(a, { name: 'Dr Bose', isOwner: true });
    await Membership.create({
      user: me.user._id,
      practice: b._id,
      role: 'doctor',
      status: 'active',
      startedOn: new Date(),
      endedOn: null,
    });

    const res = await as(me.token).get('/practices/mine', {
      'x-medpin-practice': String(b._id),
    });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.practice.name, 'City Care');
  });

  test('somebody with no membership gets no practice, not the first one', async () => {
    await makePractice('Somebody Else’s Clinic');
    const orphan = await makePractice('Holder');
    const person = await makeMember(orphan, { name: 'Dr Nobody' });
    await Membership.updateMany({ user: person.user._id }, { $set: { endedOn: new Date() } });

    const res = await as(person.token).get('/practices/mine');
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.practice, null);
  });
});
