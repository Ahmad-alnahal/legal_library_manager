// lib/features/duplicates/domain/entities/duplicate_group_details.dart

import 'package:equatable/equatable.dart';

import 'duplicate_group_file_item.dart';
import 'duplicate_group_summary.dart';

/// Full read-only details for one duplicate group, including all members.
class DuplicateGroupDetails extends Equatable {
  const DuplicateGroupDetails({
    required this.summary,
    required this.members,
    this.notes,
  });

  final DuplicateGroupSummary summary;
  final List<DuplicateGroupFileItem> members;
  final String? notes;

  @override
  List<Object?> get props => [summary, members, notes];
}
