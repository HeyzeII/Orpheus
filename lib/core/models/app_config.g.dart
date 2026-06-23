// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_config.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetAppConfigCollection on Isar {
  IsarCollection<AppConfig> get appConfigs => this.collection();
}

const AppConfigSchema = CollectionSchema(
  name: r'AppConfig',
  id: -7085420701237142207,
  properties: {
    r'conflictResolution': PropertySchema(
      id: 0,
      name: r'conflictResolution',
      type: IsarType.object,
      target: r'ConflictResolution',
    ),
    r'scanDirectories': PropertySchema(
      id: 1,
      name: r'scanDirectories',
      type: IsarType.stringList,
    ),
    r'theme': PropertySchema(
      id: 2,
      name: r'theme',
      type: IsarType.string,
    )
  },
  estimateSize: _appConfigEstimateSize,
  serialize: _appConfigSerialize,
  deserialize: _appConfigDeserialize,
  deserializeProp: _appConfigDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {
    r'ConflictResolution': ConflictResolutionSchema,
    r'IgnoredArtistPair': IgnoredArtistPairSchema
  },
  getId: _appConfigGetId,
  getLinks: _appConfigGetLinks,
  attach: _appConfigAttach,
  version: '3.1.0+1',
);

int _appConfigEstimateSize(
  AppConfig object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 +
      ConflictResolutionSchema.estimateSize(object.conflictResolution,
          allOffsets[ConflictResolution]!, allOffsets);
  bytesCount += 3 + object.scanDirectories.length * 3;
  {
    for (var i = 0; i < object.scanDirectories.length; i++) {
      final value = object.scanDirectories[i];
      bytesCount += value.length * 3;
    }
  }
  bytesCount += 3 + object.theme.length * 3;
  return bytesCount;
}

void _appConfigSerialize(
  AppConfig object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeObject<ConflictResolution>(
    offsets[0],
    allOffsets,
    ConflictResolutionSchema.serialize,
    object.conflictResolution,
  );
  writer.writeStringList(offsets[1], object.scanDirectories);
  writer.writeString(offsets[2], object.theme);
}

AppConfig _appConfigDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = AppConfig();
  object.conflictResolution = reader.readObjectOrNull<ConflictResolution>(
        offsets[0],
        ConflictResolutionSchema.deserialize,
        allOffsets,
      ) ??
      ConflictResolution();
  object.id = id;
  object.scanDirectories = reader.readStringList(offsets[1]) ?? [];
  object.theme = reader.readString(offsets[2]);
  return object;
}

P _appConfigDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readObjectOrNull<ConflictResolution>(
            offset,
            ConflictResolutionSchema.deserialize,
            allOffsets,
          ) ??
          ConflictResolution()) as P;
    case 1:
      return (reader.readStringList(offset) ?? []) as P;
    case 2:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _appConfigGetId(AppConfig object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _appConfigGetLinks(AppConfig object) {
  return [];
}

void _appConfigAttach(IsarCollection<dynamic> col, Id id, AppConfig object) {
  object.id = id;
}

extension AppConfigQueryWhereSort
    on QueryBuilder<AppConfig, AppConfig, QWhere> {
  QueryBuilder<AppConfig, AppConfig, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension AppConfigQueryWhere
    on QueryBuilder<AppConfig, AppConfig, QWhereClause> {
  QueryBuilder<AppConfig, AppConfig, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterWhereClause> idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension AppConfigQueryFilter
    on QueryBuilder<AppConfig, AppConfig, QFilterCondition> {
  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition>
      scanDirectoriesElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'scanDirectories',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition>
      scanDirectoriesElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'scanDirectories',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition>
      scanDirectoriesElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'scanDirectories',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition>
      scanDirectoriesElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'scanDirectories',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition>
      scanDirectoriesElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'scanDirectories',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition>
      scanDirectoriesElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'scanDirectories',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition>
      scanDirectoriesElementContains(String value,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'scanDirectories',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition>
      scanDirectoriesElementMatches(String pattern,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'scanDirectories',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition>
      scanDirectoriesElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'scanDirectories',
        value: '',
      ));
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition>
      scanDirectoriesElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'scanDirectories',
        value: '',
      ));
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition>
      scanDirectoriesLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'scanDirectories',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition>
      scanDirectoriesIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'scanDirectories',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition>
      scanDirectoriesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'scanDirectories',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition>
      scanDirectoriesLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'scanDirectories',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition>
      scanDirectoriesLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'scanDirectories',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition>
      scanDirectoriesLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'scanDirectories',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition> themeEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'theme',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition> themeGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'theme',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition> themeLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'theme',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition> themeBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'theme',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition> themeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'theme',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition> themeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'theme',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition> themeContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'theme',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition> themeMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'theme',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition> themeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'theme',
        value: '',
      ));
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition> themeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'theme',
        value: '',
      ));
    });
  }
}

extension AppConfigQueryObject
    on QueryBuilder<AppConfig, AppConfig, QFilterCondition> {
  QueryBuilder<AppConfig, AppConfig, QAfterFilterCondition> conflictResolution(
      FilterQuery<ConflictResolution> q) {
    return QueryBuilder.apply(this, (query) {
      return query.object(q, r'conflictResolution');
    });
  }
}

extension AppConfigQueryLinks
    on QueryBuilder<AppConfig, AppConfig, QFilterCondition> {}

extension AppConfigQuerySortBy on QueryBuilder<AppConfig, AppConfig, QSortBy> {
  QueryBuilder<AppConfig, AppConfig, QAfterSortBy> sortByTheme() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'theme', Sort.asc);
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterSortBy> sortByThemeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'theme', Sort.desc);
    });
  }
}

extension AppConfigQuerySortThenBy
    on QueryBuilder<AppConfig, AppConfig, QSortThenBy> {
  QueryBuilder<AppConfig, AppConfig, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterSortBy> thenByTheme() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'theme', Sort.asc);
    });
  }

  QueryBuilder<AppConfig, AppConfig, QAfterSortBy> thenByThemeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'theme', Sort.desc);
    });
  }
}

extension AppConfigQueryWhereDistinct
    on QueryBuilder<AppConfig, AppConfig, QDistinct> {
  QueryBuilder<AppConfig, AppConfig, QDistinct> distinctByScanDirectories() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'scanDirectories');
    });
  }

  QueryBuilder<AppConfig, AppConfig, QDistinct> distinctByTheme(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'theme', caseSensitive: caseSensitive);
    });
  }
}

extension AppConfigQueryProperty
    on QueryBuilder<AppConfig, AppConfig, QQueryProperty> {
  QueryBuilder<AppConfig, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<AppConfig, ConflictResolution, QQueryOperations>
      conflictResolutionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'conflictResolution');
    });
  }

  QueryBuilder<AppConfig, List<String>, QQueryOperations>
      scanDirectoriesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'scanDirectories');
    });
  }

  QueryBuilder<AppConfig, String, QQueryOperations> themeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'theme');
    });
  }
}

// **************************************************************************
// IsarEmbeddedGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

const IgnoredArtistPairSchema = Schema(
  name: r'IgnoredArtistPair',
  id: 8888230028501859057,
  properties: {
    r'artistA': PropertySchema(
      id: 0,
      name: r'artistA',
      type: IsarType.string,
    ),
    r'artistB': PropertySchema(
      id: 1,
      name: r'artistB',
      type: IsarType.string,
    )
  },
  estimateSize: _ignoredArtistPairEstimateSize,
  serialize: _ignoredArtistPairSerialize,
  deserialize: _ignoredArtistPairDeserialize,
  deserializeProp: _ignoredArtistPairDeserializeProp,
);

int _ignoredArtistPairEstimateSize(
  IgnoredArtistPair object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.artistA.length * 3;
  bytesCount += 3 + object.artistB.length * 3;
  return bytesCount;
}

void _ignoredArtistPairSerialize(
  IgnoredArtistPair object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.artistA);
  writer.writeString(offsets[1], object.artistB);
}

IgnoredArtistPair _ignoredArtistPairDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = IgnoredArtistPair();
  object.artistA = reader.readString(offsets[0]);
  object.artistB = reader.readString(offsets[1]);
  return object;
}

P _ignoredArtistPairDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

extension IgnoredArtistPairQueryFilter
    on QueryBuilder<IgnoredArtistPair, IgnoredArtistPair, QFilterCondition> {
  QueryBuilder<IgnoredArtistPair, IgnoredArtistPair, QAfterFilterCondition>
      artistAEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'artistA',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<IgnoredArtistPair, IgnoredArtistPair, QAfterFilterCondition>
      artistAGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'artistA',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<IgnoredArtistPair, IgnoredArtistPair, QAfterFilterCondition>
      artistALessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'artistA',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<IgnoredArtistPair, IgnoredArtistPair, QAfterFilterCondition>
      artistABetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'artistA',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<IgnoredArtistPair, IgnoredArtistPair, QAfterFilterCondition>
      artistAStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'artistA',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<IgnoredArtistPair, IgnoredArtistPair, QAfterFilterCondition>
      artistAEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'artistA',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<IgnoredArtistPair, IgnoredArtistPair, QAfterFilterCondition>
      artistAContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'artistA',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<IgnoredArtistPair, IgnoredArtistPair, QAfterFilterCondition>
      artistAMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'artistA',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<IgnoredArtistPair, IgnoredArtistPair, QAfterFilterCondition>
      artistAIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'artistA',
        value: '',
      ));
    });
  }

  QueryBuilder<IgnoredArtistPair, IgnoredArtistPair, QAfterFilterCondition>
      artistAIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'artistA',
        value: '',
      ));
    });
  }

  QueryBuilder<IgnoredArtistPair, IgnoredArtistPair, QAfterFilterCondition>
      artistBEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'artistB',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<IgnoredArtistPair, IgnoredArtistPair, QAfterFilterCondition>
      artistBGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'artistB',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<IgnoredArtistPair, IgnoredArtistPair, QAfterFilterCondition>
      artistBLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'artistB',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<IgnoredArtistPair, IgnoredArtistPair, QAfterFilterCondition>
      artistBBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'artistB',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<IgnoredArtistPair, IgnoredArtistPair, QAfterFilterCondition>
      artistBStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'artistB',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<IgnoredArtistPair, IgnoredArtistPair, QAfterFilterCondition>
      artistBEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'artistB',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<IgnoredArtistPair, IgnoredArtistPair, QAfterFilterCondition>
      artistBContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'artistB',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<IgnoredArtistPair, IgnoredArtistPair, QAfterFilterCondition>
      artistBMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'artistB',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<IgnoredArtistPair, IgnoredArtistPair, QAfterFilterCondition>
      artistBIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'artistB',
        value: '',
      ));
    });
  }

  QueryBuilder<IgnoredArtistPair, IgnoredArtistPair, QAfterFilterCondition>
      artistBIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'artistB',
        value: '',
      ));
    });
  }
}

extension IgnoredArtistPairQueryObject
    on QueryBuilder<IgnoredArtistPair, IgnoredArtistPair, QFilterCondition> {}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

const ConflictResolutionSchema = Schema(
  name: r'ConflictResolution',
  id: -2937564510210349847,
  properties: {
    r'ignoredPairs': PropertySchema(
      id: 0,
      name: r'ignoredPairs',
      type: IsarType.objectList,
      target: r'IgnoredArtistPair',
    )
  },
  estimateSize: _conflictResolutionEstimateSize,
  serialize: _conflictResolutionSerialize,
  deserialize: _conflictResolutionDeserialize,
  deserializeProp: _conflictResolutionDeserializeProp,
);

int _conflictResolutionEstimateSize(
  ConflictResolution object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.ignoredPairs.length * 3;
  {
    final offsets = allOffsets[IgnoredArtistPair]!;
    for (var i = 0; i < object.ignoredPairs.length; i++) {
      final value = object.ignoredPairs[i];
      bytesCount +=
          IgnoredArtistPairSchema.estimateSize(value, offsets, allOffsets);
    }
  }
  return bytesCount;
}

void _conflictResolutionSerialize(
  ConflictResolution object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeObjectList<IgnoredArtistPair>(
    offsets[0],
    allOffsets,
    IgnoredArtistPairSchema.serialize,
    object.ignoredPairs,
  );
}

ConflictResolution _conflictResolutionDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = ConflictResolution();
  object.ignoredPairs = reader.readObjectList<IgnoredArtistPair>(
        offsets[0],
        IgnoredArtistPairSchema.deserialize,
        allOffsets,
        IgnoredArtistPair(),
      ) ??
      [];
  return object;
}

P _conflictResolutionDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readObjectList<IgnoredArtistPair>(
            offset,
            IgnoredArtistPairSchema.deserialize,
            allOffsets,
            IgnoredArtistPair(),
          ) ??
          []) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

extension ConflictResolutionQueryFilter
    on QueryBuilder<ConflictResolution, ConflictResolution, QFilterCondition> {
  QueryBuilder<ConflictResolution, ConflictResolution, QAfterFilterCondition>
      ignoredPairsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'ignoredPairs',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<ConflictResolution, ConflictResolution, QAfterFilterCondition>
      ignoredPairsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'ignoredPairs',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<ConflictResolution, ConflictResolution, QAfterFilterCondition>
      ignoredPairsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'ignoredPairs',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<ConflictResolution, ConflictResolution, QAfterFilterCondition>
      ignoredPairsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'ignoredPairs',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<ConflictResolution, ConflictResolution, QAfterFilterCondition>
      ignoredPairsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'ignoredPairs',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<ConflictResolution, ConflictResolution, QAfterFilterCondition>
      ignoredPairsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'ignoredPairs',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }
}

extension ConflictResolutionQueryObject
    on QueryBuilder<ConflictResolution, ConflictResolution, QFilterCondition> {
  QueryBuilder<ConflictResolution, ConflictResolution, QAfterFilterCondition>
      ignoredPairsElement(FilterQuery<IgnoredArtistPair> q) {
    return QueryBuilder.apply(this, (query) {
      return query.object(q, r'ignoredPairs');
    });
  }
}
