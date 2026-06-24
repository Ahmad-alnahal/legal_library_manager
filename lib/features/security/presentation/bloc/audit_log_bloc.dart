import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/load_audit_log.dart';
import '../../application/unauthorized_exception.dart';
import 'audit_log_event.dart';
import 'audit_log_state.dart';

class AuditLogBloc extends Bloc<AuditLogEvent, AuditLogState> {
  AuditLogBloc({required this._loadAuditLog}) : super(const AuditLogInitial()) {
    on<AuditLogLoadRequested>(_onLoadRequested);
    on<AuditLogLoadMoreRequested>(_onLoadMoreRequested);
  }

  final LoadAuditLog _loadAuditLog;
  static const _pageSize = 25;

  Future<void> _onLoadRequested(
    AuditLogLoadRequested event,
    Emitter<AuditLogState> emit,
  ) async {
    emit(const AuditLogLoading());
    try {
      final events = await _loadAuditLog(limit: _pageSize, offset: 0);
      emit(AuditLogLoaded(events: events, hasMore: events.length == _pageSize));
    } on UnauthorizedException {
      emit(const AuditLogError('unauthorized'));
    } catch (_) {
      emit(const AuditLogError('unexpectedError'));
    }
  }

  Future<void> _onLoadMoreRequested(
    AuditLogLoadMoreRequested event,
    Emitter<AuditLogState> emit,
  ) async {
    final current = state;
    if (current is! AuditLogLoaded) return;
    emit(AuditLogLoadingMore(events: current.events));
    try {
      final more = await _loadAuditLog(
        limit: _pageSize,
        offset: current.events.length,
      );
      emit(
        AuditLogLoaded(
          events: [...current.events, ...more],
          hasMore: more.length == _pageSize,
        ),
      );
    } on UnauthorizedException {
      emit(const AuditLogError('unauthorized'));
    } catch (_) {
      emit(AuditLogLoaded(events: current.events, hasMore: current.hasMore));
    }
  }
}
