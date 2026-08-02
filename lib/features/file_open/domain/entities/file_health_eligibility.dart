// lib/features/file_open/domain/entities/file_health_eligibility.dart

import '../../../../core/constants/domain_keys.dart';

/// Returns true if [fileHealthKey] permits opening the file directly.
///
/// Only 'healthy' files may be opened as files. Any other status — corrupted,
/// unreadable, missing, or unknown — blocks the direct file open while still
/// allowing the containing folder to be revealed via [OpenTarget.folder].
///
/// This is the single authoritative source of the health/open eligibility rule.
/// Presentation code must call this predicate; it must not compare health
/// strings independently.
bool canOpenFileDirectly(String fileHealthKey) =>
    fileHealthKey == FileHealthKey.healthy;
