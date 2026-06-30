import 'package:equatable/equatable.dart';

import '../../domain/entities/legislation_relation.dart';

enum LegislationRelationStatus { initial, loading, success, failure }

class LegislationRelationState extends Equatable {
  const LegislationRelationState({
    this.status = LegislationRelationStatus.initial,
    this.outgoing = const [],
    this.incoming = const [],
    this.error,
  });

  final LegislationRelationStatus status;
  final List<LegislationRelation> outgoing;
  final List<LegislationRelation> incoming;
  final String? error;

  bool get isLoading => status == LegislationRelationStatus.loading;

  LegislationRelationState copyWith({
    LegislationRelationStatus? status,
    List<LegislationRelation>? outgoing,
    List<LegislationRelation>? incoming,
    String? error,
    bool clearError = false,
  }) {
    return LegislationRelationState(
      status: status ?? this.status,
      outgoing: outgoing ?? this.outgoing,
      incoming: incoming ?? this.incoming,
      error: clearError ? null : error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [status, outgoing, incoming, error];
}
