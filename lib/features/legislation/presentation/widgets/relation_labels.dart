// Localized labels for legislation relation types and scopes.
// Keys are the stable DB keys stored in `legislation_relations`.
import '../../../../l10n/app_localizations.dart';

Map<String, String> relationTypeSourceLabels(AppLocalizations l10n) => {
  'repeals': l10n.legislationRelTypeSourceRepeals,
  'amends': l10n.legislationRelTypeSourceAmends,
  'implements': l10n.legislationRelTypeSourceImplements,
  'based_on': l10n.legislationRelTypeSourceBasedOn,
  'supersedes': l10n.legislationRelTypeSourceSupersedes,
};

Map<String, String> relationTypeTargetLabels(AppLocalizations l10n) => {
  'repeals': l10n.legislationRelTypeTargetRepeals,
  'amends': l10n.legislationRelTypeTargetAmends,
  'implements': l10n.legislationRelTypeTargetImplements,
  'based_on': l10n.legislationRelTypeTargetBasedOn,
  'supersedes': l10n.legislationRelTypeTargetSupersedes,
};

Map<String, String> relationScopeLabels(AppLocalizations l10n) => {
  'full': l10n.legislationRelScopeFull,
  'partial': l10n.legislationRelScopePartial,
  'unknown': l10n.legislationRelScopeUnknown,
};
