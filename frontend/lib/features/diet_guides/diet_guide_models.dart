import 'dart:convert';

/// A long-form imported diet guide (the API's `/diet-guides`, backed by the
/// `dbo.DietPlans` article library).
///
/// Deliberately a separate type from `DietPlan` in the `diet_plans` feature:
/// that one is the day-by-day meal-schedule builder backed by
/// `dbo.NutritionPlans`. These guides are read-only reference reading.
class DietGuide {
  final String dietGuideId;
  final String title;
  final String? summary;
  final String? imageUrl;
  final String? sourceUrl;
  final String? sourceAuthor;

  /// How many ordered sections the guide has, so the card can show a length
  /// hint without loading the body.
  final int sectionCount;

  const DietGuide({
    required this.dietGuideId,
    required this.title,
    this.summary,
    this.imageUrl,
    this.sourceUrl,
    this.sourceAuthor,
    this.sectionCount = 0,
  });

  factory DietGuide.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return DietGuide(
      dietGuideId: map['dietGuideId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      summary: map['summary'] as String?,
      imageUrl: map['imageUrl'] as String?,
      sourceUrl: map['sourceUrl'] as String?,
      sourceAuthor: map['sourceAuthor'] as String?,
      sectionCount: (map['sectionCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One ordered section of a [DietGuide]. Source lists and tables are preserved
/// verbatim by the backend as JSON, so they are decoded here rather than being
/// flattened away.
class DietGuideSection {
  final String dietGuideSectionId;
  final int sortOrder;
  final String? heading;
  final String? bodyText;

  /// Each entry is one source list (e.g. a bullet list of guidelines).
  final List<List<String>> lists;

  /// Each entry is one source table; each table is a list of rows, and each row
  /// maps a column header to its cell text.
  final List<List<Map<String, String>>> tables;

  const DietGuideSection({
    required this.dietGuideSectionId,
    required this.sortOrder,
    this.heading,
    this.bodyText,
    this.lists = const [],
    this.tables = const [],
  });

  factory DietGuideSection.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return DietGuideSection(
      dietGuideSectionId: map['dietGuideSectionId'] as String? ?? '',
      sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
      heading: map['heading'] as String?,
      bodyText: map['bodyText'] as String?,
      lists: _decodeLists(map['listsJson']),
      tables: _decodeTables(map['tablesJson']),
    );
  }
}

class DietGuideDetail {
  final DietGuide guide;
  final List<DietGuideSection> sections;

  const DietGuideDetail({required this.guide, required this.sections});

  factory DietGuideDetail.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return DietGuideDetail(
      guide: DietGuide.fromJson(map['guide']),
      sections: (map['sections'] as List<dynamic>? ?? const [])
          .map(DietGuideSection.fromJson)
          .toList(),
    );
  }
}

/// Tolerates a null/blank column or malformed JSON: a guide with one unreadable
/// section should still render the rest rather than failing the whole screen.
List<List<String>> _decodeLists(dynamic raw) {
  if (raw is! String || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<List<dynamic>>()
        .map((group) => group.map((value) => value?.toString() ?? '').toList())
        .where((group) => group.any((value) => value.isNotEmpty))
        .toList();
  } catch (_) {
    return const [];
  }
}

List<List<Map<String, String>>> _decodeTables(dynamic raw) {
  if (raw is! String || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final tables = <List<Map<String, String>>>[];
    for (final table in decoded) {
      if (table is! List) continue;
      final rows = <Map<String, String>>[];
      for (final row in table) {
        if (row is! Map) continue;
        rows.add(row.map(
            (key, value) => MapEntry(key.toString(), value?.toString() ?? '')));
      }
      if (rows.isNotEmpty) tables.add(rows);
    }
    return tables;
  } catch (_) {
    return const [];
  }
}
