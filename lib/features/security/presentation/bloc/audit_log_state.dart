import 'package:equatable/equatable.dart';

import '../../domain/entities/security_audit_event.dart';

sealed class AuditLogState extends Equatable {
  const AuditLogState();

  @override
  List<Object?> get props => [];
}

final class AuditLogInitial extends AuditLogState {
  const AuditLogInitial();
}

final class AuditLogLoading extends AuditLogState {
  const AuditLogLoading();
}

final class AuditLogLoaded extends AuditLogState {
  const AuditLogLoaded({required this.events, required this.hasMore});

  final List<SecurityAuditEvent> events;
  final bool hasMore;

  @override
  List<Object?> get props => [events, hasMore];
}

final class AuditLogLoadingMore extends AuditLogState {
  const AuditLogLoadingMore({required this.events});

  final List<SecurityAuditEvent> events;

  @override
  List<Object?> get props => [events];
}

final class AuditLogError extends AuditLogState {
  const AuditLogError(this.messageKey);

  final String messageKey;

  @override
  List<Object?> get props => [messageKey];
}
