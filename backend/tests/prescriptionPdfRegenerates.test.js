import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import fs from 'node:fs/promises';
import os from 'node:os';

import mongoose from 'mongoose';
import { MongoMemoryServer } from 'mongodb-memory-server';

/**
 * A prescription whose PDF is no longer on the disk.
 *
 * ---- What happened ------------------------------------------------------
 *
 * test2 was stood up by restoring test1's database — 37,629 documents — onto a
 * fresh box. The uploads directory did not come with it. Every prescription in
 * that database already carried a `pdfFile`, so the cache branch handed back a
 * path to a file that was not there, `res.sendFile` failed, and the doctor's
 * screen said "Could not open the prescription" about a prescription that was
 * perfectly fine.
 *
 * It is not only a restore. A file can go missing from a backup rotation, a
 * disk swap, a cleanup that was too broad. In every case the document is still
 * derivable: it is rendered from the record, and the letterhead it was issued
 * under is kept on the prescription itself rather than only inside the file.
 *
 * So the cache is only a cache.
 */

let mongod;
let uploads;
let ensurePrescriptionPdf;
let MediaAsset;
let Prescription;
let User;

before(async () => {
  uploads = await fs.mkdtemp(path.join(os.tmpdir(), 'medpin-uploads-'));
  process.env.UPLOAD_DIR = uploads;
  process.env.NODE_ENV = 'test';
  process.env.JWT_SECRET ??= 'test-secret-for-prescription-pdf-regeneration';

  mongod = await MongoMemoryServer.create();
  await mongoose.connect(mongod.getUri(), { dbName: 'pdf_test' });

  ({ ensurePrescriptionPdf } = await import('../src/services/prescriptionPdf.js'));
  ({ MediaAsset } = await import('../src/models/MediaAsset.js'));
  ({ Prescription } = await import('../src/models/Prescription.js'));
  ({ User } = await import('../src/models/User.js'));
});

after(async () => {
  await mongoose.disconnect();
  await mongod?.stop();
  await fs.rm(uploads, { recursive: true, force: true });
});

async function aPrescription() {
  const patient = await User.create({
    name: 'Salman Ahmed',
    phone: `+9197${Date.now().toString().slice(-8)}`,
    role: 'patient',
  });
  const doctor = await User.create({
    name: 'Dr. Test',
    phone: `+9198${Date.now().toString().slice(-8)}`,
    role: 'doctor',
  });
  const prescription = await Prescription.create({
    patient: patient._id,
    doctor: doctor._id,
    referenceNo: `RX-${Date.now()}`,
    issuedOn: new Date(),
    items: [{ name: 'Metformin', strength: '500 mg', frequency: '1-0-1' }],
  });
  return prescription.toObject();
}

describe('the generated PDF is a cache, not the record', () => {
  test('a prescription with no PDF yet gets one, written where it says', async () => {
    const prescription = await aPrescription();

    const { asset, filePath } = await ensurePrescriptionPdf(prescription);

    const stat = await fs.stat(filePath);
    assert.ok(stat.size > 0, 'the PDF was written');
    assert.equal(asset.mimeType, 'application/pdf');

    const saved = await Prescription.findById(prescription._id).lean();
    assert.equal(String(saved.pdfFile), String(asset._id), 'the prescription points at it');
  });

  test('the same prescription hands back the same file rather than rendering again', async () => {
    const prescription = await aPrescription();

    const first = await ensurePrescriptionPdf(prescription);
    const again = await ensurePrescriptionPdf(
      await Prescription.findById(prescription._id).lean(),
    );

    assert.equal(again.filePath, first.filePath);
    assert.equal(String(again.asset._id), String(first.asset._id));
  });

  test('a PDF the disk has lost is rendered again instead of handed over missing', async () => {
    const prescription = await aPrescription();
    const first = await ensurePrescriptionPdf(prescription);

    // The restore: the row survives, the file does not.
    await fs.rm(first.filePath);

    const again = await ensurePrescriptionPdf(
      await Prescription.findById(prescription._id).lean(),
    );

    const stat = await fs.stat(again.filePath);
    assert.ok(stat.size > 0, 'it rendered a new one');
    assert.notEqual(again.filePath, first.filePath, 'and it is a new file');

    const saved = await Prescription.findById(prescription._id).lean();
    assert.equal(
      String(saved.pdfFile),
      String(again.asset._id),
      'the prescription now points at the file that exists',
    );
  });

  test('an empty file counts as lost — half a write is not a document', async () => {
    const prescription = await aPrescription();
    const first = await ensurePrescriptionPdf(prescription);

    await fs.writeFile(first.filePath, '');

    const again = await ensurePrescriptionPdf(
      await Prescription.findById(prescription._id).lean(),
    );
    const stat = await fs.stat(again.filePath);
    assert.ok(stat.size > 0);
  });
});
