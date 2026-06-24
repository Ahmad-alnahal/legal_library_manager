import 'package:equatable/equatable.dart';

/// A single security event record from the append-only audit log.
///
/// [eventDataSafe] must never contain passwords, keys, document contents,
/// or file paths beyond safe identifiers. It holds only auxiliary context
/// (e.g. operation name, outcome code) that cannot be used to reconstruct
/// a secret or locate a file.
class SecurityAuditEvent extends Equatable {
  const SecurityAuditEvent({
    required this.id,
    required this.eventTypeKey,
    required this.createdAt,
    this.actorAccountId,
    this.targetAccountId,
    this.eventDataSafe,
  });

  final int id;
  final String eventTypeKey;
  final DateTime createdAt;
  final String? actorAccountId;
  final String? targetAccountId;
  final String? eventDataSafe;

  @override
  List<Object?> get props => [
    id,
    eventTypeKey,
    createdAt,
    actorAccountId,
    targetAccountId,
    eventDataSafe,
  ];
}
