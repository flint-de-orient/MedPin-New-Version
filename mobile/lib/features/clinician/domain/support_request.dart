/// A question this clinic asked MedPin, and what MedPin said back.
///
/// ---- Why the clinic sees a thread and not a ticket number ----------------
///
/// A reference exists — six characters somebody can read out on the phone —
/// but it is not what the screen leads with. What a doctor wants to know is
/// whether anybody has answered, and a list of numbers answers that worse than
/// a list of last replies.
class SupportRequest {
  const SupportRequest({
    required this.id,
    required this.reference,
    required this.topic,
    required this.message,
    required this.state,
    required this.replies,
    this.appVersion,
    this.createdAt,
    this.lastReplyAt,
  });

  final String id;

  /// Six characters that name this request without naming the patient, the
  /// practice or the account. Said out loud on a phone call.
  final String reference;

  /// `access`, `prescribing`, `scheduling`, `billing`, `bug` or `other`.
  final String topic;

  final String message;

  /// `open`, `answered` or `closed`.
  final String state;

  final List<SupportReply> replies;

  /// The build it was raised from. Shown back, because it is part of what was
  /// said and a doctor who has since updated should be able to see that the
  /// answer was about an older app.
  final String? appVersion;

  final DateTime? createdAt;

  /// When MedPin last wrote. Null while nobody has.
  final DateTime? lastReplyAt;

  /// Whether MedPin has written and the clinic has not answered since.
  ///
  /// Not a read receipt: there is none, and a dot that claimed to know what
  /// somebody had read would be claiming something the server cannot see. It
  /// means exactly "the last word is ours".
  bool get awaitingClinic =>
      state == 'answered' && replies.isNotEmpty && replies.last.fromMedPin;

  factory SupportRequest.fromJson(Map<String, dynamic> json) {
    DateTime? at(String key) =>
        DateTime.tryParse(json[key]?.toString() ?? '')?.toLocal();

    return SupportRequest(
      id: json['id']?.toString() ?? '',
      reference: json['reference']?.toString() ?? '',
      topic: json['topic']?.toString() ?? 'other',
      message: json['message']?.toString() ?? '',
      state: json['state']?.toString() ?? 'open',
      replies: ((json['replies'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SupportReply.fromJson)
          .toList(),
      appVersion: json['appVersion']?.toString(),
      createdAt: at('createdAt'),
      lastReplyAt: at('lastReplyAt'),
    );
  }
}

class SupportReply {
  const SupportReply({required this.text, required this.fromMedPin, this.at});

  final String text;

  /// True for MedPin's side. There is no author name on ours: an operator is
  /// not a user of this app, and a name on the reply would be a person a
  /// clinic starts asking for by name.
  final bool fromMedPin;

  final DateTime? at;

  factory SupportReply.fromJson(Map<String, dynamic> json) => SupportReply(
    text: json['text']?.toString() ?? '',
    fromMedPin: json['by']?.toString() == 'medpin',
    at: DateTime.tryParse(json['at']?.toString() ?? '')?.toLocal(),
  );
}

/// What a request can be about, in the words the form offers.
///
/// Mirrors `SUPPORT_TOPIC` in backend models/SupportRequest.js. Each is named
/// for the thing that has gone wrong rather than the part of the app it lives
/// in — somebody whose prescription printed without a registration number does
/// not know that is "the letterhead".
const supportTopics = <String, String>{
  'access': 'Cannot sign in',
  'prescribing': 'Prescriptions and letterhead',
  'scheduling': 'Appointments and the queue',
  'billing': 'Plan, invoices or payouts',
  'bug': 'Something is broken',
  'other': 'Something else',
};

String supportTopicLabel(String topic) => supportTopics[topic] ?? 'Something else';

/// What a request's state is called, and whether it needs the clinic.
(String, bool) supportStateLabel(SupportRequest r) {
  if (r.state == 'closed') return ('Closed', false);
  if (r.awaitingClinic) return ('MedPin replied', true);
  if (r.state == 'answered') return ('Answered', false);
  return ('Waiting on MedPin', false);
}
