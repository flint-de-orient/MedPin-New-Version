import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../clinician/data/checkout.dart';
import 'appointment_repository.dart';

/// Paying a consultation fee, end to end.
///
/// ---- Three steps, and the third is the one that counts ---------------------
///
///   1. the server makes an order for what its own price list says is owed
///   2. Razorpay's sheet takes the money and hands back three strings
///   3. the server checks the signature over them and records the payment
///
/// Step 2 reporting success is not payment. It is a claim made by a phone, and
/// a phone can be made to claim anything — so nothing is marked paid until the
/// server has verified an HMAC only Razorpay could have produced. That is why
/// this returns the *server's* answer and never the SDK's.
///
/// ---- What a lost third step means ------------------------------------------
///
/// The money moved and this app does not know it. That is a real outcome on a
/// phone in a lift, and the honest thing to say is that it is being confirmed
/// rather than that it failed — a patient told "payment failed" after their
/// bank debited them will pay again.
enum FeeOutcome {
  /// The server verified it. The only outcome that means paid.
  paid,

  /// The patient closed the sheet. Nothing was taken and the order stands.
  cancelled,

  /// Razorpay refused it — a declined card, an expired mandate.
  failed,

  /// Taken, but this app could not get the confirmation recorded. Not a
  /// failure, and emphatically not a reason to ask again.
  unconfirmed,

  /// Never started: no fee owed, the clinic does not collect online, or the
  /// order could not be made.
  notStarted,
}

class FeeResult {
  const FeeResult(this.outcome, {this.message});

  final FeeOutcome outcome;
  final String? message;

  bool get paid => outcome == FeeOutcome.paid;
}

/// Opens checkout for one appointment's fee and reports what the server says.
///
/// [description] is what the sheet prints over the amount, so it should name
/// the visit the patient is paying for and not the app.
///
/// [describe] turns a thrown error into a sentence. Passed in rather than
/// resolved here because this function spans three awaits and a payment sheet,
/// and reaching for a BuildContext after all that is how a disposed widget's
/// localisations get read. The caller holds one that is still alive.
Future<FeeResult> payAppointmentFee(
  WidgetRef ref, {
  required String appointmentId,
  required String description,
  required String Function(Object error) describe,
}) async {
  final repo = ref.read(appointmentRepositoryProvider);
  final user = ref.read(authControllerProvider).user;
  final checkout = RazorpayCheckout();

  try {
    final order = await repo.feeOrder(appointmentId);
    if (order.keyId.isEmpty || order.orderId.isEmpty) {
      return const FeeResult(
        FeeOutcome.notStarted,
        message: 'Online payment is not switched on for this clinic.',
      );
    }

    final sheet = await checkout.openOrder(
      keyId: order.keyId,
      orderId: order.orderId,
      amountPaise: order.amountPaise,
      description: description,
      contact: user?.phone,
      email: user?.email,
    );

    switch (sheet.outcome) {
      case CheckoutOutcome.cancelled:
        return FeeResult(FeeOutcome.cancelled, message: sheet.message);
      case CheckoutOutcome.failed:
        return FeeResult(FeeOutcome.failed, message: sheet.message);
      case CheckoutOutcome.couldNotOpen:
        return FeeResult(FeeOutcome.notStarted, message: sheet.message);
      case CheckoutOutcome.paid:
        break;
    }

    final paymentId = sheet.paymentId;
    final signature = sheet.signature;
    if (paymentId == null || signature == null) {
      // Razorpay said paid and gave us nothing to prove it with. The money is
      // theirs to confirm; it is not ours to claim.
      return const FeeResult(
        FeeOutcome.unconfirmed,
        message: 'Your payment went through and is being confirmed.',
      );
    }

    try {
      await repo.verifyFee(
        appointmentId,
        paymentId: paymentId,
        signature: signature,
        orderId: sheet.orderId,
      );
      return const FeeResult(FeeOutcome.paid);
    } catch (e) {
      // Taken, not recorded. See the note on [FeeOutcome.unconfirmed].
      return FeeResult(
        FeeOutcome.unconfirmed,
        message: 'Your payment went through. We could not confirm it just now '
            '— it will show as paid shortly. ${describe(e)}',
      );
    }
  } catch (e) {
    return FeeResult(FeeOutcome.notStarted, message: describe(e));
  } finally {
    checkout.dispose();
  }
}
