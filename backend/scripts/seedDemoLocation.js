/**
 * Adds a second location to a practice, so the multi-location screens have
 * something to show.
 *
 * ---- Why this script exists ----------------------------------------------
 *
 * Several controls only appear where a practice has more than one location:
 * the Locations tick boxes on the People screens, the location filter on
 * Reports, the "which waiting room is this" question on the queue, and the
 * overlap warning when the same doctor is given hours at two branches on the
 * same morning. With one location each of those is correctly invisible, and
 * none of it can be looked at.
 *
 * So this writes one real `Clinic` row. Not a mock and not a fixture: the
 * screens read it through the same routes a clinic's own second branch would
 * go through, which is the only way to find out whether they work.
 *
 * ---- What it is careful about ---------------------------------------------
 *
 * It names no doctor and publishes no hours against anybody. A location with
 * hours is a location patients can book into, and a demo row that quietly
 * became bookable would put real patients in a waiting room that does not
 * exist. Hours are the practice's to set, on the Schedules screen, which is
 * also the screen worth testing with this.
 *
 * It refuses to exceed the practice's location limit, for the same reason the
 * route does: a seed that walks past a cap teaches nobody anything about
 * whether the cap works.
 *
 * It is idempotent by name. Run twice and the second run reports the row it
 * already made rather than making a second one.
 *
 *   node scripts/seedDemoLocation.js                      # report only
 *   node scripts/seedDemoLocation.js --apply              # write it
 *   node scripts/seedDemoLocation.js --apply --practice=<id>
 *   node scripts/seedDemoLocation.js --apply --name="City Care — New Town"
 *   node scripts/seedDemoLocation.js --remove --apply     # take it away again
 */
import mongoose from 'mongoose';

import { env } from '../src/config/env.js';
import { Clinic } from '../src/models/Clinic.js';
import { Practice } from '../src/models/Practice.js';
import { Availability } from '../src/models/Availability.js';

const apply = process.argv.includes('--apply');
const remove = process.argv.includes('--remove');

function arg(name) {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : null;
}

/**
 * The row.
 *
 * Deliberately plain. A demo address that looked like a real clinic's would
 * eventually be read as one — by a patient on a map link, or by whoever next
 * audits the location list. "Demo" is in the name on purpose, and the name is
 * what every screen shows.
 */
const DEMO = {
  name: 'Demo Branch — New Town',
  kind: 'clinic',
  addressLine: 'AA-II, New Town',
  city: 'Kolkata',
  landmark: 'For testing the multi-location screens',
};

async function main() {
  await mongoose.connect(env.MONGODB_URI);

  const practice = arg('practice')
    ? await Practice.findById(arg('practice'))
    : // The only practice, where there is only one. Guessing between several
      // would be guessing which clinic gets a demo row in its location list.
      await oneOnly();

  if (!practice) {
    console.log(
      'No practice chosen. Pass --practice=<id>, or run `node scripts/listPractices.js` if there is more than one.',
    );
    return;
  }

  const name = arg('name') ?? DEMO.name;
  const existing = await Clinic.findOne({ practice: practice._id, name });

  if (remove) {
    if (!existing) {
      console.log(`Nothing to remove: ${practice.name} has no location called "${name}".`);
      return;
    }
    /*
     * A location somebody has published hours against is a location with
     * bookings behind it. Removing it would leave appointments pointing at a
     * row that no longer exists, so this stops and says what to do.
     */
    const diaries = await Availability.countDocuments({ location: existing._id });
    if (diaries > 0) {
      console.log(
        `"${name}" has ${diaries} doctor ${diaries === 1 ? 'diary' : 'diaries'} against it. ` +
          'Clear those on the Schedules screen first — deleting it now would leave appointments pointing at nothing.',
      );
      return;
    }
    if (!apply) {
      console.log(`Would remove "${name}" from ${practice.name}. Re-run with --apply.`);
      return;
    }
    await Clinic.deleteOne({ _id: existing._id });
    console.log(`Removed "${name}" from ${practice.name}.`);
    return;
  }

  if (existing) {
    console.log(
      `${practice.name} already has "${name}" (${existing._id}). Nothing to do.`,
    );
    return;
  }

  const open = await Clinic.countDocuments({ practice: practice._id, isActive: true });
  const over = practice.overLimit('locations', open + 1);
  if (over) {
    console.log(
      `${practice.name} is limited to ${over.cap} ${over.cap === 1 ? 'location' : 'locations'} and has ${open}. ` +
        'Raise the limit on the practice first — walking past it here would not tell you whether the cap works.',
    );
    return;
  }

  if (!apply) {
    console.log(
      `Would add "${name}" to ${practice.name} (${open} ${open === 1 ? 'location' : 'locations'} today).\n` +
        'No doctor and no hours: a location with hours is a location patients can book into.\n' +
        'Re-run with --apply.',
    );
    return;
  }

  const row = await Clinic.create({
    ...DEMO,
    name,
    practice: practice._id,
    isActive: true,
    // Empty, said explicitly rather than left to the default, because this is
    // the field that decides whether patients can book here.
    weeklyHours: [],
  });

  console.log(
    `Added "${row.name}" to ${practice.name} (${row._id}).\n\n` +
      'Now visible on: People (the Locations tick boxes), the patient queue\n' +
      '(which waiting room is this), Reports (the location filter) and\n' +
      'Schedules and slots. Publish hours there to make it bookable.',
  );
}

/** The practice, when there is exactly one. */
async function oneOnly() {
  const rows = await Practice.find({}).select('name limits').limit(2);
  if (rows.length === 1) return rows[0];
  if (rows.length > 1) {
    console.log('More than one practice:');
    for (const p of await Practice.find({}).select('name')) {
      console.log(`  ${p._id}  ${p.name}`);
    }
  }
  return null;
}

main()
  .then(() => mongoose.disconnect())
  .catch(async (err) => {
    console.error(err);
    await mongoose.disconnect().catch(() => {});
    process.exitCode = 1;
  });
