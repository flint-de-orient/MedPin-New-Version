import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';

/// How a checkout ended.
///
/// Four outcomes and not two, because "it did not succeed" covers three very
/// different things and the screen should say which. A cancelled checkout is
/// somebody changing their mind and needs no apology; a failed one is a card
/// that was declined and needs a retry; an unopened one is our problem.
enum CheckoutOutcome { paid, cancelled, failed, couldNotOpen }

class CheckoutResult {
  const CheckoutResult(
    this.outcome, {
    this.paymentId,
    this.signature,
    this.orderId,
    this.message,
  });

  final CheckoutOutcome outcome;

  /// Only on [CheckoutOutcome.paid], and only meaningful once the server has
  /// verified the signature over them. See [BillingRepository.verify].
  final String? paymentId;
  final String? signature;

  /// On an order payment, which order it was for. The server knows the
  /// appointment's own order, and a mismatch is refused there rather than
  /// trusted from here.
  final String? orderId;

  final String? message;

  bool get paid => outcome == CheckoutOutcome.paid;
}

/// Razorpay's native checkout, as a Future.
///
/// ---- Why this exists rather than calling the plugin from a widget -------
///
/// The plugin is event-based: you attach three listeners, call `open`, and one
/// of them fires later. A widget doing that has to hold subscriptions, remember
/// to clear them, and cope with the sheet closing while a rebuild is in flight.
/// This turns it into one awaited call whose listeners are attached and torn
/// down in the same place.
///
/// ---- What the result does NOT mean --------------------------------------
///
/// [CheckoutOutcome.paid] means Razorpay's SDK reported success on this device.
/// It is not payment. The three fields go to the server, which checks a
/// signature only Razorpay could have produced, and the plan moves when the
/// webhook confirms money arrived. A success here that never reaches the server
/// is a customer who paid and is still on their old plan — which is why the
/// caller reports the ids rather than celebrating.
class RazorpayCheckout {
  Razorpay? _razorpay;
  Completer<CheckoutResult>? _pending;

  /// Open checkout for an existing subscription and wait for it to close.
  ///
  /// `subscriptionId` is created by our server, never by the app: a client that
  /// could name its own subscription could name a cheaper one.
  Future<CheckoutResult> open({
    required String keyId,
    required String subscriptionId,
    required String planName,
    String? contact,
    String? email,
    String brandName = 'MedPin',
    String? brandImageUrl,
  }) async {
    // One at a time. Two open sheets would race their callbacks into whichever
    // completer was last assigned, and the loser would hang for ever.
    if (_pending != null && !_pending!.isCompleted) {
      return const CheckoutResult(
        CheckoutOutcome.couldNotOpen,
        message: 'A payment is already open.',
      );
    }

    final completer = Completer<CheckoutResult>();
    _pending = completer;

    final razorpay = Razorpay();
    _razorpay = razorpay;

    void finish(CheckoutResult result) {
      if (!completer.isCompleted) completer.complete(result);
    }

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      finish(
        CheckoutResult(
          CheckoutOutcome.paid,
          paymentId: r.paymentId,
          signature: r.signature,
        ),
      );
    });

    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      // Razorpay reports a user-cancelled sheet as an error with its own code.
      // Reporting that as a failure would tell somebody their card was declined
      // when they simply pressed back.
      final cancelled = r.code == Razorpay.PAYMENT_CANCELLED;
      finish(
        CheckoutResult(
          cancelled ? CheckoutOutcome.cancelled : CheckoutOutcome.failed,
          message: cancelled ? null : _readable(r.message),
        ),
      );
    });

    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {
      // The customer left for a wallet app. Whether they paid is not knowable
      // here and arrives by webhook, so this is neither a success nor a failure.
      finish(
        const CheckoutResult(
          CheckoutOutcome.cancelled,
          message: 'Continue in your wallet app. We will update this when the '
              'payment is confirmed.',
        ),
      );
    });

    try {
      razorpay.open({
        'key': keyId,
        'subscription_id': subscriptionId,
        // Branding, which is the whole reason for using the SDK over the hosted
        // page: that page prints the Razorpay account holder's name and has no
        // override, so a MedPin customer was being asked to pay someone called
        // TANMOY DAS.
        'name': brandName,
        'description': planName,
        if (brandImageUrl != null && brandImageUrl.isNotEmpty) 'image': brandImageUrl,
        'prefill': {
          if (contact != null && contact.isNotEmpty) 'contact': contact,
          if (email != null && email.isNotEmpty) 'email': email,
        },
        'theme': {'color': '#003399'},
        // A subscription is a mandate. Letting somebody close the sheet by
        // tapping outside it, mid-authorisation, is how a half-set-up mandate
        // happens.
        'modal': {'confirm_close': true},
      });
    } catch (err) {
      finish(
        CheckoutResult(
          CheckoutOutcome.couldNotOpen,
          message: 'Could not open the payment screen.',
        ),
      );
    }

    try {
      return await completer.future;
    } finally {
      // Always, on every path. The plugin holds a platform channel listener and
      // leaving it attached across screens is how a later payment's callback
      // arrives at a disposed widget.
      razorpay.clear();
      if (identical(_razorpay, razorpay)) _razorpay = null;
      if (identical(_pending, completer)) _pending = null;
    }
  }

  /// Open checkout for one payment, on an order our server created.
  ///
  /// ---- A different Razorpay object from a subscription --------------------
  ///
  /// A subscription payment carries `subscription_id` and no amount: the plan
  /// says what it costs. A one-off carries `order_id` *and* `amount`, and the
  /// amount here is only what the sheet prints — Razorpay charges what the
  /// order says, and the order was created by the server. So a tampered amount
  /// on this side makes the sheet lie and takes the real money anyway, which
  /// is why the verify route reads the figure off the order rather than off
  /// anything the phone sent.
  ///
  /// [orderId] is never named by the app for the same reason the subscription
  /// id is not: a client that could name its own order could name a cheaper
  /// one.
  Future<CheckoutResult> openOrder({
    required String keyId,
    required String orderId,
    required int amountPaise,
    required String description,
    String? contact,
    String? email,
    String brandName = 'MedPin',
    String? brandImageUrl,
  }) async {
    if (_pending != null && !_pending!.isCompleted) {
      return const CheckoutResult(
        CheckoutOutcome.couldNotOpen,
        message: 'A payment is already open.',
      );
    }

    final completer = Completer<CheckoutResult>();
    _pending = completer;

    final razorpay = Razorpay();
    _razorpay = razorpay;

    void finish(CheckoutResult result) {
      if (!completer.isCompleted) completer.complete(result);
    }

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      finish(
        CheckoutResult(
          CheckoutOutcome.paid,
          paymentId: r.paymentId,
          signature: r.signature,
          orderId: r.orderId ?? orderId,
        ),
      );
    });

    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      final cancelled = r.code == Razorpay.PAYMENT_CANCELLED;
      finish(
        CheckoutResult(
          cancelled ? CheckoutOutcome.cancelled : CheckoutOutcome.failed,
          message: cancelled ? null : _readable(r.message),
        ),
      );
    });

    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {
      finish(
        const CheckoutResult(
          CheckoutOutcome.cancelled,
          message: 'Continue in your wallet app. We will update this when the '
              'payment is confirmed.',
        ),
      );
    });

    try {
      razorpay.open({
        'key': keyId,
        'order_id': orderId,
        'amount': amountPaise,
        'currency': 'INR',
        'name': brandName,
        'description': description,
        if (brandImageUrl != null && brandImageUrl.isNotEmpty) 'image': brandImageUrl,
        'prefill': {
          if (contact != null && contact.isNotEmpty) 'contact': contact,
          if (email != null && email.isNotEmpty) 'email': email,
        },
        'theme': {'color': '#003399'},
        // Unlike a subscription mandate, closing this by tapping outside costs
        // the patient nothing: the order stays, and the next tap reuses it.
        'modal': {'confirm_close': false},
      });
    } catch (err) {
      finish(
        const CheckoutResult(
          CheckoutOutcome.couldNotOpen,
          message: 'Could not open the payment screen.',
        ),
      );
    }

    try {
      return await completer.future;
    } finally {
      razorpay.clear();
      if (identical(_razorpay, razorpay)) _razorpay = null;
      if (identical(_pending, completer)) _pending = null;
    }
  }

  /// Tear down without waiting, for a screen being disposed mid-checkout.
  void dispose() {
    _razorpay?.clear();
    _razorpay = null;
    if (_pending != null && !_pending!.isCompleted) {
      _pending!.complete(
        const CheckoutResult(CheckoutOutcome.cancelled),
      );
    }
    _pending = null;
  }

  /// Razorpay's messages are usually a JSON blob with the real text inside.
  static String _readable(String? raw) {
    if (raw == null || raw.isEmpty) return 'The payment did not go through.';
    final match = RegExp(r'"description"\s*:\s*"([^"]+)"').firstMatch(raw);
    return match?.group(1) ?? raw;
  }
}
