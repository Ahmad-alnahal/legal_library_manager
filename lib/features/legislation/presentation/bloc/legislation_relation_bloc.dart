import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/time/clock.dart';
import '../../domain/usecases/create_legislation_relation.dart';
import '../../domain/usecases/delete_legislation_relation.dart';
import '../../domain/usecases/list_incoming_relations.dart';
import '../../domain/usecases/list_outgoing_relations.dart';
import 'legislation_relation_event.dart';
import 'legislation_relation_state.dart';

class LegislationRelationBloc
    extends Bloc<LegislationRelationEvent, LegislationRelationState> {
  LegislationRelationBloc({
    required this.listOutgoing,
    required this.listIncoming,
    required this.createRelation,
    required this.deleteRelation,
    required this.clock,
  }) : super(const LegislationRelationState()) {
    on<LegislationRelationsLoaded>(_onLoaded);
    on<LegislationRelationCreateRequested>(_onCreateRequested);
    on<LegislationRelationDeleteRequested>(_onDeleteRequested);
  }

  final ListOutgoingRelations listOutgoing;
  final ListIncomingRelations listIncoming;
  final CreateLegislationRelation createRelation;
  final DeleteLegislationRelation deleteRelation;
  final Clock clock;

  Future<void> _onLoaded(
    LegislationRelationsLoaded event,
    Emitter<LegislationRelationState> emit,
  ) async {
    emit(
      state.copyWith(
        status: LegislationRelationStatus.loading,
        clearError: true,
      ),
    );
    try {
      final outgoing = await listOutgoing(event.documentId);
      final incoming = await listIncoming(event.documentId);
      emit(
        state.copyWith(
          status: LegislationRelationStatus.success,
          outgoing: outgoing,
          incoming: incoming,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: LegislationRelationStatus.failure,
          error: e.toString(),
        ),
      );
    }
  }

  Future<void> _onCreateRequested(
    LegislationRelationCreateRequested event,
    Emitter<LegislationRelationState> emit,
  ) async {
    try {
      await createRelation(event.input, now: clock.nowUtc());
      final outgoing = await listOutgoing(event.documentId);
      final incoming = await listIncoming(event.documentId);
      emit(
        state.copyWith(
          status: LegislationRelationStatus.success,
          outgoing: outgoing,
          incoming: incoming,
          clearError: true,
        ),
      );
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onDeleteRequested(
    LegislationRelationDeleteRequested event,
    Emitter<LegislationRelationState> emit,
  ) async {
    try {
      await deleteRelation(event.relationId);
      final outgoing = await listOutgoing(event.documentId);
      final incoming = await listIncoming(event.documentId);
      emit(
        state.copyWith(
          status: LegislationRelationStatus.success,
          outgoing: outgoing,
          incoming: incoming,
          clearError: true,
        ),
      );
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }
}
