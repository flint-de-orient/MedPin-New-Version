import { test, describe, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { boot, shutdown, wipe, as } from './helpers/httpHarness.js';
import { makePractice, makeMember, makePatient } from './helpers/factories.js';
import { Practice } from '../src/models/Practice.js';
import { SupportRequest } from '../src/models/SupportRequest.js';

/**
 * Where a practice's money goes, and how a clinic asks us for help.
 *
 * ---- What is worth testing about a bank account --------------------------
 *
 * Not that four strings round-trip. The two things that cause a transfer to
 * leave and not arrive, and the one thing that leaks:
 *
 *   · a half-described account is refused — an IFSC with no number behind it,
 *     or a number with no name, is an account that does not exist, and the
 *     bank says so days later as a returned payment;
 *   · the account number never comes back out, in any response, ever;
 *   · an operator's confirmation that money reached the account survives the
 *     clinic editing its bank name, and does not survive a new account.
 *
 * ---- And about support ----------------------------------------------------
 *
 * That a clinic reads its own requests and nobody else's, including a
 * colleague at the same practice — a request may be about that colleague.
 */

describe('the payout account', () => {
  before(boot);
  after(shutdown);
  beforeEach(wipe);

  async function clinic() {
    const practice = await makePractice('City Care');
    const head = await makeMember(practice, { name: 'Dr Sen', isOwner: true });
    return { practice, head };
  }

  const good = {
    accountName: 'City Care Clinic',
    accountNumber: '50100234567890',
    ifsc: 'HDFC0001234',
    bankName: 'HDFC, Salt Lake',
    upiId: null,
  };

  test('a whole account saves, and comes back without the number', async () => {
    const { practice, head } = await clinic();

    const res = await as(head.token).patch(`/practices/${practice._id}`, {
      payout: good,
    });
    assert.equal(res.status, 200, JSON.stringify(res.body));

    const p = res.body.practice.payout;
    assert.equal(p.accountName, 'City Care Clinic');
    assert.equal(p.ifsc, 'HDFC0001234');
    assert.equal(p.accountLast4, '7890');
    assert.equal(p.onFile, true);

    // The whole point of the field being `select: false`.
    assert.equal(p.accountNumber, undefined);
    assert.ok(
      !JSON.stringify(res.body).includes('50100234567890'),
      'the account number must not appear anywhere in the response',
    );
  });

  test('the number is absent from the practice read as well', async () => {
    const { practice, head } = await clinic();
    await as(head.token).patch(`/practices/${practice._id}`, { payout: good });

    const res = await as(head.token).get('/practices/mine');
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.ok(
      !JSON.stringify(res.body).includes('50100234567890'),
      'a practice read must not carry the account number either',
    );
  });

  test('an account with no IFSC and no UPI is refused', async () => {
    const { practice, head } = await clinic();

    const res = await as(head.token).patch(`/practices/${practice._id}`, {
      payout: { ...good, ifsc: null },
    });
    assert.equal(res.status, 400, JSON.stringify(res.body));

    const after = await Practice.findById(practice._id).lean();
    assert.ok(!after.payout?.accountLast4, 'nothing was written');
  });

  test('a bank account with no account holder name is refused', async () => {
    const { practice, head } = await clinic();

    const res = await as(head.token).patch(`/practices/${practice._id}`, {
      payout: { ...good, accountName: null },
    });
    assert.equal(res.status, 400, JSON.stringify(res.body));
  });

  test('UPI alone is enough', async () => {
    const { practice, head } = await clinic();

    const res = await as(head.token).patch(`/practices/${practice._id}`, {
      payout: {
        accountName: null,
        accountNumber: null,
        ifsc: null,
        bankName: null,
        upiId: 'citycare@okaxis',
      },
    });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.practice.payout.upiId, 'citycare@okaxis');
    assert.equal(res.body.practice.payout.onFile, true);
    assert.equal(res.body.practice.payout.accountLast4, null);
  });

  test('a malformed IFSC is refused before the bank sees it', async () => {
    const { practice, head } = await clinic();

    for (const ifsc of ['HDFC1001234', 'HDFC000123', 'hdfc0001234x']) {
      const res = await as(head.token).patch(`/practices/${practice._id}`, {
        payout: { ...good, ifsc },
      });
      assert.equal(res.status, 400, `${ifsc}: ${JSON.stringify(res.body)}`);
    }
  });

  test('a lower-case IFSC is accepted and stored upper-case', async () => {
    const { practice, head } = await clinic();

    const res = await as(head.token).patch(`/practices/${practice._id}`, {
      payout: { ...good, ifsc: 'hdfc0001234' },
    });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.practice.payout.ifsc, 'HDFC0001234');
  });

  test('editing the bank name keeps the confirmation; a new account clears it', async () => {
    const { practice, head } = await clinic();
    await as(head.token).patch(`/practices/${practice._id}`, { payout: good });

    // What an operator does once a transfer has actually arrived.
    const confirmed = new Date('2026-09-01T00:00:00.000Z');
    await Practice.updateOne(
      { _id: practice._id },
      { $set: { 'payout.verifiedAt': confirmed } },
    );

    const same = await as(head.token).patch(`/practices/${practice._id}`, {
      payout: { ...good, bankName: 'HDFC, Sector V' },
    });
    assert.equal(same.status, 200, JSON.stringify(same.body));
    assert.equal(
      new Date(same.body.practice.payout.verifiedAt).toISOString(),
      confirmed.toISOString(),
      'a clinic correcting its branch name has not changed where the money goes',
    );

    const moved = await as(head.token).patch(`/practices/${practice._id}`, {
      payout: { ...good, accountNumber: '50100999888777' },
    });
    assert.equal(moved.status, 200, JSON.stringify(moved.body));
    assert.equal(
      moved.body.practice.payout.verifiedAt,
      null,
      'a different account has had nothing confirmed about it',
    );
    assert.equal(moved.body.practice.payout.accountLast4, '8777');
  });

  test('somebody who cannot manage the practice cannot move its money', async () => {
    const { practice } = await clinic();
    const desk = await makeMember(practice, { name: 'Tania', role: 'staff' });

    const res = await as(desk.token).patch(`/practices/${practice._id}`, {
      payout: good,
    });
    assert.ok(res.status === 403 || res.status === 404, `got ${res.status}`);

    const after = await Practice.findById(practice._id).lean();
    assert.ok(!after.payout?.accountLast4, 'nothing was written');
  });
});

describe('asking MedPin for help', () => {
  before(boot);
  after(shutdown);
  beforeEach(wipe);

  async function clinic() {
    const practice = await makePractice('City Care');
    const head = await makeMember(practice, { name: 'Dr Sen', isOwner: true });
    const desk = await makeMember(practice, { name: 'Tania', role: 'staff' });
    return { practice, head, desk };
  }

  test('a request is raised, and carries the practice and the build', async () => {
    const { practice, head } = await clinic();

    const res = await as(head.token).post('/support', {
      topic: 'prescribing',
      message: 'Tapping Print on a prescription does nothing.',
      appVersion: '1.0.73',
      platform: 'android',
    });
    assert.equal(res.status, 201, JSON.stringify(res.body));
    assert.equal(res.body.request.topic, 'prescribing');
    assert.equal(res.body.request.state, 'open');
    assert.equal(res.body.request.appVersion, '1.0.73');
    assert.equal(res.body.request.reference.length, 6);

    const row = await SupportRequest.findById(res.body.request.id).lean();
    assert.equal(String(row.practice), String(practice._id));
    assert.equal(String(row.raisedBy), String(head.user._id));
  });

  test('a message too short to act on is refused', async () => {
    const { head } = await clinic();

    const res = await as(head.token).post('/support', {
      topic: 'bug',
      message: 'broken',
    });
    assert.equal(res.status, 400, JSON.stringify(res.body));
  });

  test('a colleague at the same practice does not read it', async () => {
    const { head, desk } = await clinic();

    await as(head.token).post('/support', {
      topic: 'access',
      message: 'Tania has locked herself out again this morning.',
    });

    const theirs = await as(desk.token).get('/support');
    assert.equal(theirs.status, 200, JSON.stringify(theirs.body));
    assert.equal(
      theirs.body.items.length,
      0,
      'a request may be about a colleague, so the practice is not the scope',
    );

    const mine = await as(head.token).get('/support');
    assert.equal(mine.body.items.length, 1);
  });

  test('a patient has no way in here', async () => {
    await clinic();
    const patient = await makePatient({ name: 'Rahul' });

    const res = await as(patient.token).post('/support', {
      topic: 'bug',
      message: 'The app will not open on my phone at all.',
    });
    assert.equal(res.status, 403, JSON.stringify(res.body));
  });

  test('the clinic can add to it, and that puts it back on us', async () => {
    const { head } = await clinic();
    const made = await as(head.token).post('/support', {
      topic: 'scheduling',
      message: 'A patient cannot book with me on Tuesdays.',
    });
    const id = made.body.request.id;

    // What an operator's reply does.
    await SupportRequest.updateOne(
      { _id: id },
      {
        $set: { state: 'answered', lastReplyAt: new Date() },
        $push: { replies: { text: 'Which location?', by: 'medpin' } },
      },
    );

    const res = await as(head.token).post(`/support/${id}/replies`, {
      text: 'Salt Lake.',
    });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.request.replies.length, 2);
    assert.equal(
      res.body.request.state,
      'open',
      'the clinic has answered, so it is ours again',
    );
  });

  test('a closed request takes no more replies, and says what to do', async () => {
    const { head } = await clinic();
    const made = await as(head.token).post('/support', {
      topic: 'other',
      message: 'How do I add a second consulting room?',
    });
    const id = made.body.request.id;

    const closed = await as(head.token).post(`/support/${id}/close`, {});
    assert.equal(closed.status, 200, JSON.stringify(closed.body));
    assert.equal(closed.body.request.state, 'closed');

    // Again: the state it is already in, not a failure.
    const twice = await as(head.token).post(`/support/${id}/close`, {});
    assert.equal(twice.status, 200);
    assert.equal(twice.body.request.state, 'closed');

    const late = await as(head.token).post(`/support/${id}/replies`, {
      text: 'Actually it has come back.',
    });
    assert.equal(late.status, 400, JSON.stringify(late.body));
    assert.match(late.body.error.message, /closed/i);
  });

  test('somebody else’s request is not found, rather than refused', async () => {
    const { head, desk } = await clinic();
    const made = await as(head.token).post('/support', {
      topic: 'billing',
      message: 'Last month’s payout has not arrived yet.',
    });

    const res = await as(desk.token).post(
      `/support/${made.body.request.id}/replies`,
      { text: 'Me too.' },
    );
    // Confirming the id exists would itself be an answer.
    assert.equal(res.status, 404, JSON.stringify(res.body));
  });
});
