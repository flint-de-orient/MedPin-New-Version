import { test, describe, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';

import mongoose from 'mongoose';
import { MongoMemoryServer } from 'mongodb-memory-server';

/**
 * What a consultation costs, and what it takes to call it paid.
 *
 * The money is the part of this system where a wrong answer is not a wrong
 * screen. So what is pinned here is the arithmetic and the trust boundary: the
 * amount comes from the practice's own row and never from the request, zero is
 * a price rather than an absence, a withdrawn service cannot be booked, and a
 * payment is believed only if Razorpay signed it.
 */

let mongod;
let Service;
let rupeesOf;
let verifyOrderSignature;

before(async () => {
  process.env.NODE_ENV = 'test';
  process.env.JWT_SECRET ??= 'test-secret-for-appointment-fees';
  process.env.RAZORPAY_KEY_ID = 'rzp_test_feetest';
  process.env.RAZORPAY_KEY_SECRET = 'fee-test-secret';
  mongod = await MongoMemoryServer.create();
  await mongoose.connect(mongod.getUri(), { dbName: 'fees_test' });

  ({ Service, rupeesOf } = await import('../src/models/Service.js'));
  ({ verifyOrderSignature } = await import('../src/services/billing/razorpay.js'));
  // The uniqueness below is the index's, and an index that has not been built
  // enforces nothing — which is also true on a server whose collection
  // predates the index, so this is worth being explicit about.
  await Service.syncIndexes();
});

after(async () => {
  await mongoose.disconnect();
  await mongod.stop();
});

const practice = new mongoose.Types.ObjectId();
const other = new mongoose.Types.ObjectId();

beforeEach(async () => {
  await Service.deleteMany({});
});

describe('the price list', () => {
  test('a fee is paise, and reads back as rupees without a float', async () => {
    const service = await Service.create({
      practice,
      name: 'Follow-up',
      amountPaise: 49999,
    });
    assert.equal(service.amountPaise, 49999);
    assert.equal(rupeesOf(service.amountPaise), '499.99');
    assert.equal(rupeesOf(50000), '500', 'a round figure is not printed as 500.00');
  });

  test('zero is a price, not a missing one', async () => {
    const service = await Service.create({
      practice,
      name: 'Follow-up within a fortnight',
      amountPaise: 0,
    });
    assert.equal(service.amountPaise, 0);
  });

  test('a negative fee is refused', async () => {
    await assert.rejects(
      () => Service.create({ practice, name: 'Refund', amountPaise: -100 }),
      /amountPaise/,
    );
  });

  test('one name per practice, so a list cannot show it twice', async () => {
    await Service.create({ practice, name: 'Follow-up', amountPaise: 30000 });
    await assert.rejects(
      () => Service.create({ practice, name: 'Follow-up', amountPaise: 40000 }),
      (err) => err.code === 11000,
    );
  });

  test('another practice may use the same name at its own price', async () => {
    await Service.create({ practice, name: 'Follow-up', amountPaise: 30000 });
    const theirs = await Service.create({
      practice: other,
      name: 'Follow-up',
      amountPaise: 20000,
    });
    assert.equal(theirs.amountPaise, 20000);
  });

  test('a doctor may price their own, beside the practice rate', async () => {
    const doctor = new mongoose.Types.ObjectId();
    await Service.create({ practice, name: 'New consultation', amountPaise: 60000 });
    const mine = await Service.create({
      practice,
      doctor,
      name: 'New consultation',
      amountPaise: 90000,
    });
    assert.equal(String(mine.doctor), String(doctor));
  });

  test('a service is for one kind of visit, or for both', async () => {
    await assert.rejects(
      () => Service.create({ practice, name: 'Odd', amountPaise: 1, mode: 'house_call' }),
      /mode/,
    );
    const both = await Service.create({ practice, name: 'Any', amountPaise: 1 });
    assert.equal(both.mode, 'both', 'the default covers a clinic visit and a video call');
  });
});

describe('a payment is believed only if Razorpay signed it', () => {
  const orderId = 'order_FEE123';
  const paymentId = 'pay_FEE123';

  function sign(order, payment, secret = 'fee-test-secret') {
    return crypto.createHmac('sha256', secret).update(`${order}|${payment}`).digest('hex');
  }

  test('the real signature passes', () => {
    assert.equal(
      verifyOrderSignature({
        orderId,
        paymentId,
        signature: sign(orderId, paymentId),
      }),
      true,
    );
  });

  test('a signature over the halves the other way round fails', () => {
    // Razorpay signs order|payment for an order and payment|subscription for a
    // subscription. Swapping them is the classic way this is got wrong, and
    // the symptom is every real payment looking forged.
    assert.equal(
      verifyOrderSignature({
        orderId,
        paymentId,
        signature: sign(paymentId, orderId),
      }),
      false,
    );
  });

  test('a signature from somebody else’s secret fails', () => {
    assert.equal(
      verifyOrderSignature({
        orderId,
        paymentId,
        signature: sign(orderId, paymentId, 'not-our-secret'),
      }),
      false,
    );
  });

  test('a payment id claimed for a different order fails', () => {
    assert.equal(
      verifyOrderSignature({
        orderId: 'order_SOMEONE_ELSE',
        paymentId,
        signature: sign(orderId, paymentId),
      }),
      false,
    );
  });

  test('nothing at all fails, rather than throwing', () => {
    assert.equal(verifyOrderSignature({}), false);
    assert.equal(
      verifyOrderSignature({ orderId, paymentId, signature: '' }),
      false,
    );
    assert.equal(
      verifyOrderSignature({ orderId, paymentId, signature: 'short' }),
      false,
      'a length mismatch is a failed comparison, not a crash',
    );
  });
});

describe('the fee an appointment carries', () => {
  let Appointment;

  before(async () => {
    ({ Appointment } = await import('../src/models/Appointment.js'));
  });

  beforeEach(async () => {
    await Appointment.deleteMany({});
  });

  test('a booking with no service owes nothing through the app', async () => {
    const appointment = await Appointment.create({
      patient: new mongoose.Types.ObjectId(),
      doctor: new mongoose.Types.ObjectId(),
      scheduledFor: new Date(Date.now() + 86_400_000),
      status: 'confirmed',
    });
    assert.equal(appointment.fee.status, 'not_required');
    assert.equal(
      appointment.fee.amountPaise,
      null,
      'null, because the desk is about to ask for cash — that is not free',
    );
  });

  test('the amount is a copy, so a later price rise does not change it', async () => {
    const service = await Service.create({
      practice,
      name: 'Follow-up',
      amountPaise: 30000,
    });
    const appointment = await Appointment.create({
      patient: new mongoose.Types.ObjectId(),
      doctor: new mongoose.Types.ObjectId(),
      scheduledFor: new Date(Date.now() + 86_400_000),
      status: 'confirmed',
      service: service._id,
      fee: { amountPaise: service.amountPaise, status: 'pending' },
    });

    service.amountPaise = 45000;
    await service.save();

    const again = await Appointment.findById(appointment._id).lean();
    assert.equal(
      again.fee.amountPaise,
      30000,
      'what February’s patient was asked for does not change in March',
    );
  });

  test('only the four states exist, and nothing else is storable', async () => {
    await assert.rejects(
      () =>
        Appointment.create({
          patient: new mongoose.Types.ObjectId(),
          doctor: new mongoose.Types.ObjectId(),
          scheduledFor: new Date(Date.now() + 86_400_000),
          status: 'confirmed',
          fee: { amountPaise: 100, status: 'probably_paid' },
        }),
      /status/,
    );
  });
});
