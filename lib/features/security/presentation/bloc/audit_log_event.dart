sealed class AuditLogEvent {
  const AuditLogEvent();
}

final class AuditLogLoadRequested extends AuditLogEvent {
  const AuditLogLoadRequested();
}

final class AuditLogLoadMoreRequested extends AuditLogEvent {
  const AuditLogLoadMoreRequested();
}
