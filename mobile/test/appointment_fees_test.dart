import 'package:flutter_test/flutter_test.dart';

import 'package:medpin/features/appointments/domain/appointment.dart';
import 'package:medpin/features/appointments/domain/service.dart';
import 'package:medpin/features/doctor_home/domain/consultation_report.dart';
import 'package:medpin/features/doctor_home/presentation/doctor_reports_screen.dart';
import 'package:medpin/features/doctor_home/presentation/doctor_report_register_screen.dart';

/// What a consultation costs, on the screens that say so.
///
/// Money is the part of this app where a wrong word is worse than a wrong
/// pixel. Three things are pinned here: that nothing charged in the app is
/// never printed as "free", that a figure covering eleven of two hundred
/// consultations cannot be shown without saying so, and that the note about
/// what the report cannot see says the thing that is true today rather than
/// the thing that was true before fees existed.

void main() {
  group('a service and its price', () {
    test('whole rupees print without decimals, and part rupees with them', () {
      expect(
        const ClinicService(id: '1', name: 'A', mode: 'both', amountPaise: 50000).price,
        '₹500',
      );
      expect(
        const ClinicService(id: '1', name: 'A', mode: 'both', amountPaise: 49999).price,
        '₹499.99',
      );
    });

    test('zero is Free, which is a price the clinic set', () {
      expect(
        const ClinicService(id: '1', name: 'A', mode: 'both', amountPaise: 0).price,
        'Free',
      );
    });

    test('a service for one kind of visit is not offered for the other', () {
      const clinicOnly = ClinicService(
        id: '1',
        name: 'A',
        mode: 'in_clinic',
        amountPaise: 1,
      );
      expect(clinicOnly.offeredFor('in_clinic'), isTrue);
      expect(clinicOnly.offeredFor('teleconsult'), isFalse);
      const either = ClinicService(id: '2', name: 'B', mode: 'both', amountPaise: 1);
      expect(either.offeredFor('teleconsult'), isTrue);
    });
  });

  group('what an appointment says about its fee', () {
    test('a visit the app does not collect for says nothing at all', () {
      const fee = AppointmentFee();
      expect(
        fee.line,
        isNull,
        reason: 'the desk is about to ask for cash — printing "Free" would be a lie',
      );
      expect(fee.owed, isFalse);
    });

    test('an unpaid fee is due, and a paid one is paid', () {
      expect(
        const AppointmentFee(amountPaise: 50000, status: 'pending').line,
        '₹500 due',
      );
      expect(
        const AppointmentFee(amountPaise: 50000, status: 'paid').line,
        '₹500 paid',
      );
      expect(
        const AppointmentFee(amountPaise: 50000, status: 'refunded').line,
        '₹500 refunded',
      );
    });

    test('a zero fee is a no-charge visit, and is never owed', () {
      const fee = AppointmentFee(amountPaise: 0, status: 'pending');
      expect(fee.line, 'No charge');
      expect(fee.owed, isFalse, reason: 'there is nothing to collect');
    });

    test('it survives a server that has never heard of fees', () {
      final a = Appointment.fromJson({
        'id': 'a1',
        'status': 'confirmed',
        'mode': 'in_clinic',
      });
      expect(a.fee.status, 'not_required');
      expect(a.fee.line, isNull);
    });
  });

  group('the money on the report', () {
    FeeTotals totals({
      int collected = 0,
      int previous = 0,
      int outstanding = 0,
      int outstandingCount = 0,
      int paidCount = 0,
      int countedOf = 0,
      int consultations = 0,
    }) => FeeTotals(
      collectedPaise: collected,
      previousCollectedPaise: previous,
      outstandingPaise: outstanding,
      outstandingCount: outstandingCount,
      paidCount: paidCount,
      countedOf: countedOf,
      consultations: consultations,
    );

    test('is grouped the Indian way', () {
      expect(totals(collected: 100000).collected, '₹1,000');
      expect(totals(collected: 2400000).collected, '₹24,000');
      expect(totals(collected: 15700000).collected, '₹1,57,000');
      expect(totals(collected: 50000).collected, '₹500');
    });

    test('never appears without how many consultations it covers', () {
      expect(
        feeCoverage(totals(countedOf: 11, consultations: 286)),
        '11 of 286 consultations',
      );
    });

    test('a change is a change, and nothing to compare says so', () {
      expect(
        deltaMoney(totals(collected: 2400000, previous: 2000000)),
        '+₹4,000 vs before',
      );
      expect(
        deltaMoney(totals(collected: 2000000, previous: 2400000)),
        '−₹4,000 vs before',
      );
      expect(deltaMoney(totals(collected: 100, previous: 0)), 'Nothing to compare');
      expect(deltaMoney(totals()), 'None before either');
      expect(deltaMoney(totals(collected: 500, previous: 500)), 'Same as before');
    });
  });

  group('the note about what the report cannot see', () {
    test('with nothing charged in the app, it says that — not that it was nil', () {
      final said = notRecordedLine(const FeeTotals());
      expect(said, contains('nothing was charged through the app'));
      expect(said, contains('Cash taken at the desk is not recorded'));
      expect(said, contains('Referrals are not on this report'));
      expect(said, contains('not because nobody was referred'));
    });

    test('with money in it, it warns that this is not the takings', () {
      final said = notRecordedLine(
        const FeeTotals(collectedPaise: 2400000, countedOf: 11, consultations: 286),
      );
      expect(said, contains('only what patients paid through the app'));
      expect(said, contains('not the practice\'s takings'));
      expect(
        said,
        isNot(contains('Fees and referrals are not on this report')),
        reason: 'the old sentence lumped the two together while neither existed',
      );
      expect(
        said,
        isNot(contains('Fees are not on this report')),
        reason: 'fees are recorded now — some of them',
      );
      expect(said, contains('Referrals are not on this report'));
    });
  });

  group('the fees register', () {
    FeeRow row({
      required int amountPaise,
      required String status,
      int? paidPaise,
    }) => FeeRow(
      id: 'a',
      patientId: 'p',
      patientName: 'Anita Sengupta',
      at: DateTime(2026, 9, 10, 10),
      amountPaise: amountPaise,
      status: status,
      paidPaise: paidPaise,
    );

    test('the heading adds up what arrived and what is still owed', () {
      final heading = feesHeading([
        row(amountPaise: 50000, status: 'paid', paidPaise: 50000),
        row(amountPaise: 30000, status: 'paid', paidPaise: 30000),
        row(amountPaise: 20000, status: 'pending'),
      ]);
      expect(heading, '₹800 paid · ₹200 still owed');
    });

    test('with nothing owed it says only what was paid', () {
      expect(
        feesHeading([row(amountPaise: 50000, status: 'paid', paidPaise: 50000)]),
        '₹500 paid',
      );
    });

    test('it adds up what arrived, not what was asked', () {
      // They differ only after a partial refund, and the day they do, a
      // heading that totalled the asking price would be the last place
      // anybody noticed.
      expect(
        feesHeading([row(amountPaise: 50000, status: 'paid', paidPaise: 30000)]),
        '₹300 paid',
      );
    });

    test('every state has a word, never a colour alone', () {
      expect(feeWord(row(amountPaise: 1, status: 'paid')), 'Paid');
      expect(feeWord(row(amountPaise: 1, status: 'pending')), 'Unpaid');
      expect(feeWord(row(amountPaise: 1, status: 'refunded')), 'Refunded');
    });
  });
}
