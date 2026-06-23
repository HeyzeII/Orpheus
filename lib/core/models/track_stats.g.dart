// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'track_stats.dart';

// **************************************************************************
// IsarEmbeddedGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

const TrackStatsSchema = Schema(
  name: r'TrackStats',
  id: 4359499609169358373,
  properties: {
    r'playCountsPerMonth': PropertySchema(
      id: 0,
      name: r'playCountsPerMonth',
      type: IsarType.longList,
    ),
    r'playMonths': PropertySchema(
      id: 1,
      name: r'playMonths',
      type: IsarType.stringList,
    ),
    r'totalPlays': PropertySchema(
      id: 2,
      name: r'totalPlays',
      type: IsarType.long,
    )
  },
  estimateSize: _trackStatsEstimateSize,
  serialize: _trackStatsSerialize,
  deserialize: _trackStatsDeserialize,
  deserializeProp: _trackStatsDeserializeProp,
);

int _trackStatsEstimateSize(
  TrackStats object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.playCountsPerMonth.length * 8;
  bytesCount += 3 + object.playMonths.length * 3;
  {
    for (var i = 0; i < object.playMonths.length; i++) {
      final value = object.playMonths[i];
      bytesCount += value.length * 3;
    }
  }
  return bytesCount;
}

void _trackStatsSerialize(
  TrackStats object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLongList(offsets[0], object.playCountsPerMonth);
  writer.writeStringList(offsets[1], object.playMonths);
  writer.writeLong(offsets[2], object.totalPlays);
}

TrackStats _trackStatsDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = TrackStats();
  object.playCountsPerMonth = reader.readLongList(offsets[0]) ?? [];
  object.playMonths = reader.readStringList(offsets[1]) ?? [];
  object.totalPlays = reader.readLong(offsets[2]);
  return object;
}

P _trackStatsDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLongList(offset) ?? []) as P;
    case 1:
      return (reader.readStringList(offset) ?? []) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

extension TrackStatsQueryFilter
    on QueryBuilder<TrackStats, TrackStats, QFilterCondition> {
  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      playCountsPerMonthElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'playCountsPerMonth',
        value: value,
      ));
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      playCountsPerMonthElementGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'playCountsPerMonth',
        value: value,
      ));
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      playCountsPerMonthElementLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'playCountsPerMonth',
        value: value,
      ));
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      playCountsPerMonthElementBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'playCountsPerMonth',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      playCountsPerMonthLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'playCountsPerMonth',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      playCountsPerMonthIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'playCountsPerMonth',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      playCountsPerMonthIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'playCountsPerMonth',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      playCountsPerMonthLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'playCountsPerMonth',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      playCountsPerMonthLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'playCountsPerMonth',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      playCountsPerMonthLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'playCountsPerMonth',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      playMonthsElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'playMonths',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      playMonthsElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'playMonths',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      playMonthsElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'playMonths',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      playMonthsElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'playMonths',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      playMonthsElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'playMonths',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      playMonthsElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'playMonths',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      playMonthsElementContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'playMonths',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      playMonthsElementMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'playMonths',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      playMonthsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'playMonths',
        value: '',
      ));
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      playMonthsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'playMonths',
        value: '',
      ));
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      playMonthsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'playMonths',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      playMonthsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'playMonths',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      playMonthsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'playMonths',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      playMonthsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'playMonths',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      playMonthsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'playMonths',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      playMonthsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'playMonths',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition> totalPlaysEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'totalPlays',
        value: value,
      ));
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      totalPlaysGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'totalPlays',
        value: value,
      ));
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition>
      totalPlaysLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'totalPlays',
        value: value,
      ));
    });
  }

  QueryBuilder<TrackStats, TrackStats, QAfterFilterCondition> totalPlaysBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'totalPlays',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension TrackStatsQueryObject
    on QueryBuilder<TrackStats, TrackStats, QFilterCondition> {}
