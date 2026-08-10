import 'package:lw_domain/lw_domain.dart';
import 'package:lw_rulepack/src/decode/primitives.dart';
import 'package:lw_rulepack/src/json_view.dart';

/// Decodes `additives/ins.json`.
///
/// Separate from the eager decoders because this segment is loaded lazily
/// (§9.2 of `ARCHITECTURE.md`): it is the pack's largest, and a nutrition-only
/// scan never touches it.
final class AdditiveDecoder {
  const AdditiveDecoder._();

  /// Decodes the whole additive table.
  static AdditiveTable decode(JsonView root) {
    final List<AdditiveRecord> decoded = <AdditiveRecord>[];
    for (final JsonView v in root.required('additives').elements) {
      try {
        decoded.add(
          AdditiveRecord(
            insNumber: InsNumber(v.required('insNumber').asInt),
            commonName: v.required('commonName').asString,
            alternateNames: <String>[
              if (v.has('alternateNames'))
                for (final JsonView n in v.required('alternateNames').elements)
                  n.asString,
            ],
            functionalClass: v
                .required('functionalClass')
                .asEnum(Primitives.functionalClasses),
            descriptionMessageId:
                v.required('descriptionMessageId').asId(MessageId.new),
            evidenceStrength: v
                .required('evidenceStrength')
                .asEnum(Primitives.evidenceStrengths),
            sourceRefs: <SourceId>[
              for (final JsonView s in v.required('sourceRefs').elements)
                s.asId(SourceId.new),
            ],
            indianPermission: _permission(v.required('indianPermission')),
          ),
        );
      } on ArgumentError catch (e) {
        // An INS number outside 1…99999, or a record with no citation.
        v.reject(RulePackFailureKind.schemaViolation, '${e.message}');
      }
    }
    try {
      return AdditiveTable(decoded);
    } on ArgumentError catch (e) {
      root.reject(RulePackFailureKind.duplicateKey, '${e.message}');
    }
  }

  static IndianPermission _permission(JsonView v) {
    final List<PermissionEvidence> evidence = <PermissionEvidence>[
      if (v.has('evidence'))
        for (final JsonView e in v.required('evidence').elements)
          PermissionEvidence(
            sourceRef: e.required('sourceRef').asId(SourceId.new),
            scheduleRef: e.required('scheduleRef').asString,
            entryName: e.required('entryName').asString,
            foodProducts: e.required('foodProducts').asString,
            limit: e.required('limit').asString,
          ),
    ];
    try {
      return IndianPermission(
        status: v.required('status').asEnum(Primitives.permissionStatuses),
        evidence: evidence,
        note: v.has('note') ? v.required('note').asString : null,
      );
    } on ArgumentError catch (e) {
      // PERMITTED with no citation. The schema has a conditional for this and
      // so does the type; both are here because CI proves the pack we shipped
      // and this proves the pack we were handed.
      v.reject(RulePackFailureKind.schemaViolation, '${e.message}');
    }
  }
}
