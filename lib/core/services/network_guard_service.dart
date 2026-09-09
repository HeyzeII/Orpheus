import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../database/local_database.dart';
import '../models/app_config.dart';

/// Outcome of evaluating network permissions against connectivity state and app settings.
enum NetworkAccessResult {
  /// Request is authorized by both offline mode and network policies.
  allowed,

  /// Request is blocked because Strict Offline Mode is enabled by the user.
  blockedByOfflineMode,

  /// Request is blocked because the active network interface (e.g. Mobile Data)
  /// is not permitted under the configured [CoverDownloadPolicy].
  blockedByCellularPolicy,

  /// Request cannot proceed because no network interface is connected.
  noInternetConnection,
}

/// Centralized service responsible for enforcing network access policies,
/// inspecting live connectivity, and gating all external HTTP requests.
///
/// ## Responsibilities:
/// 1. **Strict Offline Mode Gate**: Immediately intercepts and halts all outgoing
///    network calls if `AppConfig.strictOfflineMode` is enabled.
/// 2. **Cellular Data Protection**: Enforces [CoverDownloadPolicy] rules (e.g.,
///    preventing expensive album art image downloads over cellular/mobile data).
/// 3. **Live Connectivity Stream**: Exposes [onConnectivityChanged] for reactive UI.
class NetworkGuardService {
  NetworkGuardService._internal({
    Connectivity? connectivity,
    LocalDatabase? db,
  })  : _connectivity = connectivity ?? Connectivity(),
        _db = db ?? LocalDatabase.instance;

  static final NetworkGuardService instance = NetworkGuardService._internal();

  factory NetworkGuardService({
    Connectivity? connectivity,
    LocalDatabase? db,
  }) {
    if (connectivity != null || db != null) {
      return NetworkGuardService._internal(
        connectivity: connectivity,
        db: db,
      );
    }
    return instance;
  }

  final Connectivity _connectivity;
  final LocalDatabase _db;

  /// Stream of live connectivity updates from the operating system.
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _connectivity.onConnectivityChanged;

  /// Evaluates whether general external HTTP requests (e.g. lyrics from LRCLIB)
  /// are allowed under current user configuration and connectivity.
  Future<NetworkAccessResult> checkGeneralAccess() async {
    final config = await _db.getConfig();

    if (config.strictOfflineMode) {
      return NetworkAccessResult.blockedByOfflineMode;
    }

    final connectivity = await _connectivity.checkConnectivity();
    if (_isDisconnected(connectivity)) {
      return NetworkAccessResult.noInternetConnection;
    }

    return NetworkAccessResult.allowed;
  }

  /// Evaluates whether album art downloads (iTunes / Apple CDN) are permitted
  /// under the configured [CoverDownloadPolicy] and connectivity state.
  Future<NetworkAccessResult> checkCoverDownloadAccess() async {
    final generalAccess = await checkGeneralAccess();
    if (generalAccess != NetworkAccessResult.allowed) {
      return generalAccess;
    }

    final config = await _db.getConfig();
    final policy = config.coverDownloadPolicy;

    if (policy == CoverDownloadPolicy.never) {
      return NetworkAccessResult.blockedByCellularPolicy;
    }

    if (policy == CoverDownloadPolicy.always) {
      return NetworkAccessResult.allowed;
    }

    // CoverDownloadPolicy.wifiOnly
    final connectivity = await _connectivity.checkConnectivity();
    final hasUnmeteredConnection = connectivity.any(
      (c) =>
          c == ConnectivityResult.wifi ||
          c == ConnectivityResult.ethernet,
    );

    if (hasUnmeteredConnection) {
      return NetworkAccessResult.allowed;
    }

    return NetworkAccessResult.blockedByCellularPolicy;
  }

  /// Convenience boolean check for general HTTP calls.
  Future<bool> canMakeGeneralRequest() async {
    final result = await checkGeneralAccess();
    return result == NetworkAccessResult.allowed;
  }

  /// Convenience boolean check for album art downloads.
  Future<bool> canDownloadCover() async {
    final result = await checkCoverDownloadAccess();
    return result == NetworkAccessResult.allowed;
  }

  /// Checks whether Strict Offline Mode is currently enabled.
  Future<bool> isOfflineMode() async {
    final config = await _db.getConfig();
    return config.strictOfflineMode;
  }

  /// Updates the Strict Offline Mode setting and persists it to Isar DB.
  Future<void> setOfflineMode(bool enabled) async {
    final config = await _db.getConfig();
    config.strictOfflineMode = enabled;
    await _db.saveConfig(config);
  }

  /// Updates the [CoverDownloadPolicy] and persists it to Isar DB.
  Future<void> setCoverDownloadPolicy(CoverDownloadPolicy policy) async {
    final config = await _db.getConfig();
    config.coverDownloadPolicy = policy;
    await _db.saveConfig(config);
  }

  /// Returns true if the connectivity list indicates no active internet interface.
  bool _isDisconnected(List<ConnectivityResult> results) {
    if (results.isEmpty) return true;
    return results.every((r) => r == ConnectivityResult.none);
  }
}
