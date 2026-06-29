// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'track.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetTrackCollection on Isar {
  IsarCollection<Track> get tracks => this.collection();
}

const TrackSchema = CollectionSchema(
  name: r'Track',
  id: 6244076704169336260,
  properties: {
    r'album': PropertySchema(
      id: 0,
      name: r'album',
      type: IsarType.string,
    ),
    r'artStatus': PropertySchema(
      id: 1,
      name: r'artStatus',
      type: IsarType.byte,
      enumMap: _TrackartStatusEnumValueMap,
    ),
    r'artist': PropertySchema(
      id: 2,
      name: r'artist',
      type: IsarType.string,
    ),
    r'customMetadata': PropertySchema(
      id: 3,
      name: r'customMetadata',
      type: IsarType.object,
      target: r'CustomMetadata',
    ),
    r'displayAlbum': PropertySchema(
      id: 4,
      name: r'displayAlbum',
      type: IsarType.string,
    ),
    r'displayArtist': PropertySchema(
      id: 5,
      name: r'displayArtist',
      type: IsarType.string,
    ),
    r'displayTitle': PropertySchema(
      id: 6,
      name: r'displayTitle',
      type: IsarType.string,
    ),
    r'downloadSource': PropertySchema(
      id: 7,
      name: r'downloadSource',
      type: IsarType.string,
    ),
    r'duration': PropertySchema(
      id: 8,
      name: r'duration',
      type: IsarType.long,
    ),
    r'filePath': PropertySchema(
      id: 9,
      name: r'filePath',
      type: IsarType.string,
    ),
    r'fileType': PropertySchema(
      id: 10,
      name: r'fileType',
      type: IsarType.byte,
      enumMap: _TrackfileTypeEnumValueMap,
    ),
    r'genre': PropertySchema(
      id: 11,
      name: r'genre',
      type: IsarType.string,
    ),
    r'hasCustomMetadata': PropertySchema(
      id: 12,
      name: r'hasCustomMetadata',
      type: IsarType.bool,
    ),
    r'lyricsStatus': PropertySchema(
      id: 13,
      name: r'lyricsStatus',
      type: IsarType.byte,
      enumMap: _TracklyricsStatusEnumValueMap,
    ),
    r'stats': PropertySchema(
      id: 14,
      name: r'stats',
      type: IsarType.object,
      target: r'TrackStats',
    ),
    r'syncedLyrics': PropertySchema(
      id: 15,
      name: r'syncedLyrics',
      type: IsarType.string,
    ),
    r'title': PropertySchema(
      id: 16,
      name: r'title',
      type: IsarType.string,
    ),
    r'trackId': PropertySchema(
      id: 17,
      name: r'trackId',
      type: IsarType.string,
    )
  },
  estimateSize: _trackEstimateSize,
  serialize: _trackSerialize,
  deserialize: _trackDeserialize,
  deserializeProp: _trackDeserializeProp,
  idName: r'id',
  indexes: {
    r'trackId': IndexSchema(
      id: -8614467705999066844,
      name: r'trackId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'trackId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'filePath': IndexSchema(
      id: 2918041768256347220,
      name: r'filePath',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'filePath',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {
    r'CustomMetadata': CustomMetadataSchema,
    r'TrackStats': TrackStatsSchema
  },
  getId: _trackGetId,
  getLinks: _trackGetLinks,
  attach: _trackAttach,
  version: '3.1.0+1',
);

int _trackEstimateSize(
  Track object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.album;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.artist;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 +
      CustomMetadataSchema.estimateSize(
          object.customMetadata, allOffsets[CustomMetadata]!, allOffsets);
  bytesCount += 3 + object.displayAlbum.length * 3;
  bytesCount += 3 + object.displayArtist.length * 3;
  bytesCount += 3 + object.displayTitle.length * 3;
  {
    final value = object.downloadSource;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.filePath.length * 3;
  {
    final value = object.genre;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 +
      TrackStatsSchema.estimateSize(
          object.stats, allOffsets[TrackStats]!, allOffsets);
  {
    final value = object.syncedLyrics;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.title;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.trackId.length * 3;
  return bytesCount;
}

void _trackSerialize(
  Track object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.album);
  writer.writeByte(offsets[1], object.artStatus.index);
  writer.writeString(offsets[2], object.artist);
  writer.writeObject<CustomMetadata>(
    offsets[3],
    allOffsets,
    CustomMetadataSchema.serialize,
    object.customMetadata,
  );
  writer.writeString(offsets[4], object.displayAlbum);
  writer.writeString(offsets[5], object.displayArtist);
  writer.writeString(offsets[6], object.displayTitle);
  writer.writeString(offsets[7], object.downloadSource);
  writer.writeLong(offsets[8], object.duration);
  writer.writeString(offsets[9], object.filePath);
  writer.writeByte(offsets[10], object.fileType.index);
  writer.writeString(offsets[11], object.genre);
  writer.writeBool(offsets[12], object.hasCustomMetadata);
  writer.writeByte(offsets[13], object.lyricsStatus.index);
  writer.writeObject<TrackStats>(
    offsets[14],
    allOffsets,
    TrackStatsSchema.serialize,
    object.stats,
  );
  writer.writeString(offsets[15], object.syncedLyrics);
  writer.writeString(offsets[16], object.title);
  writer.writeString(offsets[17], object.trackId);
}

Track _trackDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = Track();
  object.album = reader.readStringOrNull(offsets[0]);
  object.artStatus =
      _TrackartStatusValueEnumMap[reader.readByteOrNull(offsets[1])] ??
          FetchStatus.none;
  object.artist = reader.readStringOrNull(offsets[2]);
  object.customMetadata = reader.readObjectOrNull<CustomMetadata>(
        offsets[3],
        CustomMetadataSchema.deserialize,
        allOffsets,
      ) ??
      CustomMetadata();
  object.downloadSource = reader.readStringOrNull(offsets[7]);
  object.duration = reader.readLong(offsets[8]);
  object.filePath = reader.readString(offsets[9]);
  object.fileType =
      _TrackfileTypeValueEnumMap[reader.readByteOrNull(offsets[10])] ??
          FileType.mp3;
  object.genre = reader.readStringOrNull(offsets[11]);
  object.hasCustomMetadata = reader.readBool(offsets[12]);
  object.id = id;
  object.lyricsStatus =
      _TracklyricsStatusValueEnumMap[reader.readByteOrNull(offsets[13])] ??
          FetchStatus.none;
  object.stats = reader.readObjectOrNull<TrackStats>(
        offsets[14],
        TrackStatsSchema.deserialize,
        allOffsets,
      ) ??
      TrackStats();
  object.syncedLyrics = reader.readStringOrNull(offsets[15]);
  object.title = reader.readStringOrNull(offsets[16]);
  object.trackId = reader.readString(offsets[17]);
  return object;
}

P _trackDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringOrNull(offset)) as P;
    case 1:
      return (_TrackartStatusValueEnumMap[reader.readByteOrNull(offset)] ??
          FetchStatus.none) as P;
    case 2:
      return (reader.readStringOrNull(offset)) as P;
    case 3:
      return (reader.readObjectOrNull<CustomMetadata>(
            offset,
            CustomMetadataSchema.deserialize,
            allOffsets,
          ) ??
          CustomMetadata()) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readString(offset)) as P;
    case 7:
      return (reader.readStringOrNull(offset)) as P;
    case 8:
      return (reader.readLong(offset)) as P;
    case 9:
      return (reader.readString(offset)) as P;
    case 10:
      return (_TrackfileTypeValueEnumMap[reader.readByteOrNull(offset)] ??
          FileType.mp3) as P;
    case 11:
      return (reader.readStringOrNull(offset)) as P;
    case 12:
      return (reader.readBool(offset)) as P;
    case 13:
      return (_TracklyricsStatusValueEnumMap[reader.readByteOrNull(offset)] ??
          FetchStatus.none) as P;
    case 14:
      return (reader.readObjectOrNull<TrackStats>(
            offset,
            TrackStatsSchema.deserialize,
            allOffsets,
          ) ??
          TrackStats()) as P;
    case 15:
      return (reader.readStringOrNull(offset)) as P;
    case 16:
      return (reader.readStringOrNull(offset)) as P;
    case 17:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

const _TrackartStatusEnumValueMap = {
  'none': 0,
  'success': 1,
  'notFound': 2,
  'custom': 3,
};
const _TrackartStatusValueEnumMap = {
  0: FetchStatus.none,
  1: FetchStatus.success,
  2: FetchStatus.notFound,
  3: FetchStatus.custom,
};
const _TrackfileTypeEnumValueMap = {
  'mp3': 0,
  'flac': 1,
  'mp4': 2,
  'm4a': 3,
  'wav': 4,
  'unknown': 5,
};
const _TrackfileTypeValueEnumMap = {
  0: FileType.mp3,
  1: FileType.flac,
  2: FileType.mp4,
  3: FileType.m4a,
  4: FileType.wav,
  5: FileType.unknown,
};
const _TracklyricsStatusEnumValueMap = {
  'none': 0,
  'success': 1,
  'notFound': 2,
  'custom': 3,
};
const _TracklyricsStatusValueEnumMap = {
  0: FetchStatus.none,
  1: FetchStatus.success,
  2: FetchStatus.notFound,
  3: FetchStatus.custom,
};

Id _trackGetId(Track object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _trackGetLinks(Track object) {
  return [];
}

void _trackAttach(IsarCollection<dynamic> col, Id id, Track object) {
  object.id = id;
}

extension TrackByIndex on IsarCollection<Track> {
  Future<Track?> getByTrackId(String trackId) {
    return getByIndex(r'trackId', [trackId]);
  }

  Track? getByTrackIdSync(String trackId) {
    return getByIndexSync(r'trackId', [trackId]);
  }

  Future<bool> deleteByTrackId(String trackId) {
    return deleteByIndex(r'trackId', [trackId]);
  }

  bool deleteByTrackIdSync(String trackId) {
    return deleteByIndexSync(r'trackId', [trackId]);
  }

  Future<List<Track?>> getAllByTrackId(List<String> trackIdValues) {
    final values = trackIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'trackId', values);
  }

  List<Track?> getAllByTrackIdSync(List<String> trackIdValues) {
    final values = trackIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'trackId', values);
  }

  Future<int> deleteAllByTrackId(List<String> trackIdValues) {
    final values = trackIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'trackId', values);
  }

  int deleteAllByTrackIdSync(List<String> trackIdValues) {
    final values = trackIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'trackId', values);
  }

  Future<Id> putByTrackId(Track object) {
    return putByIndex(r'trackId', object);
  }

  Id putByTrackIdSync(Track object, {bool saveLinks = true}) {
    return putByIndexSync(r'trackId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByTrackId(List<Track> objects) {
    return putAllByIndex(r'trackId', objects);
  }

  List<Id> putAllByTrackIdSync(List<Track> objects, {bool saveLinks = true}) {
    return putAllByIndexSync(r'trackId', objects, saveLinks: saveLinks);
  }

  Future<Track?> getByFilePath(String filePath) {
    return getByIndex(r'filePath', [filePath]);
  }

  Track? getByFilePathSync(String filePath) {
    return getByIndexSync(r'filePath', [filePath]);
  }

  Future<bool> deleteByFilePath(String filePath) {
    return deleteByIndex(r'filePath', [filePath]);
  }

  bool deleteByFilePathSync(String filePath) {
    return deleteByIndexSync(r'filePath', [filePath]);
  }

  Future<List<Track?>> getAllByFilePath(List<String> filePathValues) {
    final values = filePathValues.map((e) => [e]).toList();
    return getAllByIndex(r'filePath', values);
  }

  List<Track?> getAllByFilePathSync(List<String> filePathValues) {
    final values = filePathValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'filePath', values);
  }

  Future<int> deleteAllByFilePath(List<String> filePathValues) {
    final values = filePathValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'filePath', values);
  }

  int deleteAllByFilePathSync(List<String> filePathValues) {
    final values = filePathValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'filePath', values);
  }

  Future<Id> putByFilePath(Track object) {
    return putByIndex(r'filePath', object);
  }

  Id putByFilePathSync(Track object, {bool saveLinks = true}) {
    return putByIndexSync(r'filePath', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByFilePath(List<Track> objects) {
    return putAllByIndex(r'filePath', objects);
  }

  List<Id> putAllByFilePathSync(List<Track> objects, {bool saveLinks = true}) {
    return putAllByIndexSync(r'filePath', objects, saveLinks: saveLinks);
  }
}

extension TrackQueryWhereSort on QueryBuilder<Track, Track, QWhere> {
  QueryBuilder<Track, Track, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension TrackQueryWhere on QueryBuilder<Track, Track, QWhereClause> {
  QueryBuilder<Track, Track, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> idNotEqualTo(Id id) {
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

  QueryBuilder<Track, Track, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> idBetween(
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

  QueryBuilder<Track, Track, QAfterWhereClause> trackIdEqualTo(String trackId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'trackId',
        value: [trackId],
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> trackIdNotEqualTo(
      String trackId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'trackId',
              lower: [],
              upper: [trackId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'trackId',
              lower: [trackId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'trackId',
              lower: [trackId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'trackId',
              lower: [],
              upper: [trackId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> filePathEqualTo(
      String filePath) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'filePath',
        value: [filePath],
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> filePathNotEqualTo(
      String filePath) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'filePath',
              lower: [],
              upper: [filePath],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'filePath',
              lower: [filePath],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'filePath',
              lower: [filePath],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'filePath',
              lower: [],
              upper: [filePath],
              includeUpper: false,
            ));
      }
    });
  }
}

extension TrackQueryFilter on QueryBuilder<Track, Track, QFilterCondition> {
  QueryBuilder<Track, Track, QAfterFilterCondition> albumIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'album',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> albumIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'album',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> albumEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'album',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> albumGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'album',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> albumLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'album',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> albumBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'album',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> albumStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'album',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> albumEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'album',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> albumContains(String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'album',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> albumMatches(String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'album',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> albumIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'album',
        value: '',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> albumIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'album',
        value: '',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artStatusEqualTo(
      FetchStatus value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'artStatus',
        value: value,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artStatusGreaterThan(
    FetchStatus value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'artStatus',
        value: value,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artStatusLessThan(
    FetchStatus value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'artStatus',
        value: value,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artStatusBetween(
    FetchStatus lower,
    FetchStatus upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'artStatus',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artistIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'artist',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artistIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'artist',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artistEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'artist',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artistGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'artist',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artistLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'artist',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artistBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'artist',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artistStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'artist',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artistEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'artist',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artistContains(String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'artist',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artistMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'artist',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artistIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'artist',
        value: '',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artistIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'artist',
        value: '',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayAlbumEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'displayAlbum',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayAlbumGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'displayAlbum',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayAlbumLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'displayAlbum',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayAlbumBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'displayAlbum',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayAlbumStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'displayAlbum',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayAlbumEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'displayAlbum',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayAlbumContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'displayAlbum',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayAlbumMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'displayAlbum',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayAlbumIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'displayAlbum',
        value: '',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayAlbumIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'displayAlbum',
        value: '',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayArtistEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'displayArtist',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayArtistGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'displayArtist',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayArtistLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'displayArtist',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayArtistBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'displayArtist',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayArtistStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'displayArtist',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayArtistEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'displayArtist',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayArtistContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'displayArtist',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayArtistMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'displayArtist',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayArtistIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'displayArtist',
        value: '',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayArtistIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'displayArtist',
        value: '',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayTitleEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'displayTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayTitleGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'displayTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayTitleLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'displayTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayTitleBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'displayTitle',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayTitleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'displayTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayTitleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'displayTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayTitleContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'displayTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayTitleMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'displayTitle',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayTitleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'displayTitle',
        value: '',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> displayTitleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'displayTitle',
        value: '',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> downloadSourceIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'downloadSource',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> downloadSourceIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'downloadSource',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> downloadSourceEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'downloadSource',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> downloadSourceGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'downloadSource',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> downloadSourceLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'downloadSource',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> downloadSourceBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'downloadSource',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> downloadSourceStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'downloadSource',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> downloadSourceEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'downloadSource',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> downloadSourceContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'downloadSource',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> downloadSourceMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'downloadSource',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> downloadSourceIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'downloadSource',
        value: '',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> downloadSourceIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'downloadSource',
        value: '',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> durationEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'duration',
        value: value,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> durationGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'duration',
        value: value,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> durationLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'duration',
        value: value,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> durationBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'duration',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> filePathEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'filePath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> filePathGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'filePath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> filePathLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'filePath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> filePathBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'filePath',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> filePathStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'filePath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> filePathEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'filePath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> filePathContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'filePath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> filePathMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'filePath',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> filePathIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'filePath',
        value: '',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> filePathIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'filePath',
        value: '',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> fileTypeEqualTo(
      FileType value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'fileType',
        value: value,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> fileTypeGreaterThan(
    FileType value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'fileType',
        value: value,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> fileTypeLessThan(
    FileType value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'fileType',
        value: value,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> fileTypeBetween(
    FileType lower,
    FileType upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'fileType',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> genreIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'genre',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> genreIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'genre',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> genreEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'genre',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> genreGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'genre',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> genreLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'genre',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> genreBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'genre',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> genreStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'genre',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> genreEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'genre',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> genreContains(String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'genre',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> genreMatches(String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'genre',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> genreIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'genre',
        value: '',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> genreIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'genre',
        value: '',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> hasCustomMetadataEqualTo(
      bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'hasCustomMetadata',
        value: value,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> idGreaterThan(
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

  QueryBuilder<Track, Track, QAfterFilterCondition> idLessThan(
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

  QueryBuilder<Track, Track, QAfterFilterCondition> idBetween(
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

  QueryBuilder<Track, Track, QAfterFilterCondition> lyricsStatusEqualTo(
      FetchStatus value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lyricsStatus',
        value: value,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> lyricsStatusGreaterThan(
    FetchStatus value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'lyricsStatus',
        value: value,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> lyricsStatusLessThan(
    FetchStatus value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'lyricsStatus',
        value: value,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> lyricsStatusBetween(
    FetchStatus lower,
    FetchStatus upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'lyricsStatus',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> syncedLyricsIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'syncedLyrics',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> syncedLyricsIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'syncedLyrics',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> syncedLyricsEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'syncedLyrics',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> syncedLyricsGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'syncedLyrics',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> syncedLyricsLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'syncedLyrics',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> syncedLyricsBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'syncedLyrics',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> syncedLyricsStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'syncedLyrics',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> syncedLyricsEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'syncedLyrics',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> syncedLyricsContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'syncedLyrics',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> syncedLyricsMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'syncedLyrics',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> syncedLyricsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'syncedLyrics',
        value: '',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> syncedLyricsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'syncedLyrics',
        value: '',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> titleIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'title',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> titleIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'title',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> titleEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> titleGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> titleLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> titleBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'title',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> titleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> titleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> titleContains(String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> titleMatches(String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'title',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> titleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> titleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> trackIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'trackId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> trackIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'trackId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> trackIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'trackId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> trackIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'trackId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> trackIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'trackId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> trackIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'trackId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> trackIdContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'trackId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> trackIdMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'trackId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> trackIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'trackId',
        value: '',
      ));
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> trackIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'trackId',
        value: '',
      ));
    });
  }
}

extension TrackQueryObject on QueryBuilder<Track, Track, QFilterCondition> {
  QueryBuilder<Track, Track, QAfterFilterCondition> customMetadata(
      FilterQuery<CustomMetadata> q) {
    return QueryBuilder.apply(this, (query) {
      return query.object(q, r'customMetadata');
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> stats(
      FilterQuery<TrackStats> q) {
    return QueryBuilder.apply(this, (query) {
      return query.object(q, r'stats');
    });
  }
}

extension TrackQueryLinks on QueryBuilder<Track, Track, QFilterCondition> {}

extension TrackQuerySortBy on QueryBuilder<Track, Track, QSortBy> {
  QueryBuilder<Track, Track, QAfterSortBy> sortByAlbum() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'album', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByAlbumDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'album', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByArtStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'artStatus', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByArtStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'artStatus', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByArtist() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'artist', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByArtistDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'artist', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByDisplayAlbum() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'displayAlbum', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByDisplayAlbumDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'displayAlbum', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByDisplayArtist() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'displayArtist', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByDisplayArtistDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'displayArtist', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByDisplayTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'displayTitle', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByDisplayTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'displayTitle', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByDownloadSource() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'downloadSource', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByDownloadSourceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'downloadSource', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByDuration() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'duration', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByDurationDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'duration', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByFilePath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'filePath', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByFilePathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'filePath', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByFileType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fileType', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByFileTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fileType', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByGenre() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'genre', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByGenreDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'genre', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByHasCustomMetadata() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasCustomMetadata', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByHasCustomMetadataDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasCustomMetadata', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByLyricsStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsStatus', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByLyricsStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsStatus', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortBySyncedLyrics() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncedLyrics', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortBySyncedLyricsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncedLyrics', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByTrackId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'trackId', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByTrackIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'trackId', Sort.desc);
    });
  }
}

extension TrackQuerySortThenBy on QueryBuilder<Track, Track, QSortThenBy> {
  QueryBuilder<Track, Track, QAfterSortBy> thenByAlbum() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'album', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByAlbumDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'album', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByArtStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'artStatus', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByArtStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'artStatus', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByArtist() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'artist', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByArtistDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'artist', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByDisplayAlbum() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'displayAlbum', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByDisplayAlbumDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'displayAlbum', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByDisplayArtist() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'displayArtist', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByDisplayArtistDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'displayArtist', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByDisplayTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'displayTitle', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByDisplayTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'displayTitle', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByDownloadSource() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'downloadSource', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByDownloadSourceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'downloadSource', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByDuration() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'duration', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByDurationDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'duration', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByFilePath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'filePath', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByFilePathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'filePath', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByFileType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fileType', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByFileTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fileType', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByGenre() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'genre', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByGenreDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'genre', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByHasCustomMetadata() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasCustomMetadata', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByHasCustomMetadataDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasCustomMetadata', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByLyricsStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsStatus', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByLyricsStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsStatus', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenBySyncedLyrics() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncedLyrics', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenBySyncedLyricsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncedLyrics', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByTrackId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'trackId', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByTrackIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'trackId', Sort.desc);
    });
  }
}

extension TrackQueryWhereDistinct on QueryBuilder<Track, Track, QDistinct> {
  QueryBuilder<Track, Track, QDistinct> distinctByAlbum(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'album', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByArtStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'artStatus');
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByArtist(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'artist', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByDisplayAlbum(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'displayAlbum', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByDisplayArtist(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'displayArtist',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByDisplayTitle(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'displayTitle', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByDownloadSource(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'downloadSource',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByDuration() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'duration');
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByFilePath(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'filePath', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByFileType() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'fileType');
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByGenre(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'genre', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByHasCustomMetadata() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'hasCustomMetadata');
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByLyricsStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lyricsStatus');
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctBySyncedLyrics(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'syncedLyrics', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByTitle(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'title', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByTrackId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'trackId', caseSensitive: caseSensitive);
    });
  }
}

extension TrackQueryProperty on QueryBuilder<Track, Track, QQueryProperty> {
  QueryBuilder<Track, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<Track, String?, QQueryOperations> albumProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'album');
    });
  }

  QueryBuilder<Track, FetchStatus, QQueryOperations> artStatusProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'artStatus');
    });
  }

  QueryBuilder<Track, String?, QQueryOperations> artistProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'artist');
    });
  }

  QueryBuilder<Track, CustomMetadata, QQueryOperations>
      customMetadataProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'customMetadata');
    });
  }

  QueryBuilder<Track, String, QQueryOperations> displayAlbumProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'displayAlbum');
    });
  }

  QueryBuilder<Track, String, QQueryOperations> displayArtistProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'displayArtist');
    });
  }

  QueryBuilder<Track, String, QQueryOperations> displayTitleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'displayTitle');
    });
  }

  QueryBuilder<Track, String?, QQueryOperations> downloadSourceProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'downloadSource');
    });
  }

  QueryBuilder<Track, int, QQueryOperations> durationProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'duration');
    });
  }

  QueryBuilder<Track, String, QQueryOperations> filePathProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'filePath');
    });
  }

  QueryBuilder<Track, FileType, QQueryOperations> fileTypeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'fileType');
    });
  }

  QueryBuilder<Track, String?, QQueryOperations> genreProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'genre');
    });
  }

  QueryBuilder<Track, bool, QQueryOperations> hasCustomMetadataProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'hasCustomMetadata');
    });
  }

  QueryBuilder<Track, FetchStatus, QQueryOperations> lyricsStatusProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lyricsStatus');
    });
  }

  QueryBuilder<Track, TrackStats, QQueryOperations> statsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'stats');
    });
  }

  QueryBuilder<Track, String?, QQueryOperations> syncedLyricsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'syncedLyrics');
    });
  }

  QueryBuilder<Track, String?, QQueryOperations> titleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'title');
    });
  }

  QueryBuilder<Track, String, QQueryOperations> trackIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'trackId');
    });
  }
}
