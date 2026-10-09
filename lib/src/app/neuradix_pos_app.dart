import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/local/hosted_local_repository.dart';
import '../data/local/local_sync_repository.dart';
import '../data/local/pos_cache_repository.dart';
import '../data/local/neuradix_database.dart';
import '../features/bootstrap/connection_error_formatter.dart';
import '../features/bootstrap/bootstrap_config.dart';
import '../features/bootstrap/bootstrap_config_repository.dart';
import '../features/bootstrap/runtime_bench_url.dart';
import '../features/hosted/hosted_models.dart';
import '../features/hosted/hosted_pos_support.dart';
import '../features/local_sync/local_sync_coordinator.dart';
import '../features/local_sync/local_sync_bootstrapper.dart';
import '../features/local_sync/local_sync_crypto.dart';
import '../features/local_sync/local_sync_ids.dart';
import '../features/local_sync/local_sync_models.dart';
import '../features/local_sync/local_sync_pairing.dart';
import '../features/local_sync/local_sync_pairing_dialog.dart';
import '../features/local_sync/local_sync_relay_worker.dart';
import '../features/local_sync/local_sync_shop_dialog.dart';
import '../features/orders/local_order_repository.dart';
import '../features/pos/catalog_image_provider.dart';
import '../features/pos/pos_debug_log.dart';
import '../features/pos/pos_home_controller.dart';
import '../features/pos/pos_models.dart';
import '../features/pos/neuradix_api_client.dart';
import '../theme/neuradix_theme.dart';

const String _dedicatedBenchUrl = String.fromEnvironment(
  'NEURADIX_DEDICATED_URL',
);

const String _compiledDefaultInstanceUrl = String.fromEnvironment(
  'NEURADIX_DEFAULT_URL',
  defaultValue: 'http://neuradix-cassar.localhost:8008',
);
const String neuradixDefaultCloudBaseUrl = String.fromEnvironment(
  'NEURADIX_CLOUD_URL',
  defaultValue: neuradixDefaultCloudBaseUrlFallback,
);
const String _defaultUatUsername = String.fromEnvironment(
  'NEURADIX_DEFAULT_USERNAME',
  defaultValue: 'sara.camilleri@neuradix.local',
);
const String _defaultUatPassword = String.fromEnvironment(
  'NEURADIX_DEFAULT_PASSWORD',
  defaultValue: 'NeuradixDemo!2026',
);

String get _defaultInstanceUrl => normalizeBenchUrlForRuntime(
  _dedicatedBenchUrl.isNotEmpty
      ? _dedicatedBenchUrl
      : _compiledDefaultInstanceUrl,
);

String get _defaultCloudBaseUrl =>
    normalizeBenchUrlForRuntime(neuradixDefaultCloudBaseUrl);

const Set<String> _legacyHostedCloudBaseUrls = <String>{
  'http://127.0.0.1:8008',
  'http://localhost:8008',
  'http://10.0.2.2:8008',
  'http://neuradix-cassar.localhost:8008',
};

String _normalizeComparableUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.endsWith('/')) {
    return trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

bool _isLegacyHostedCloudBaseUrl(String url) {
  return _legacyHostedCloudBaseUrls.contains(_normalizeComparableUrl(url));
}

bool _sameBootstrapConfig(BootstrapConfig left, BootstrapConfig right) {
  final leftMap = left.asMap();
  final rightMap = right.asMap();
  if (leftMap.length != rightMap.length) {
    return false;
  }
  for (final entry in leftMap.entries) {
    if (rightMap[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

bool posOrderUsesCompactLayout(
  double maxWidth, {
  double maxHeight = double.infinity,
}) => maxWidth < 1040 || maxHeight < 650;

double posOrderCartPanelWidth(double maxWidth) {
  if (posOrderUsesCompactLayout(maxWidth)) {
    return double.infinity;
  }
  return maxWidth < 1280 ? 340.0 : 405.0;
}

bool hostedSalesUsesCompactLayout(double maxWidth) => maxWidth < 920;

bool hostedSalesUsesScrollableNonCompactPane({
  required double maxWidth,
  required double maxHeight,
}) => !hostedSalesUsesCompactLayout(maxWidth) && maxHeight < 620;

double hostedCompactBodyHeight(double maxHeight) {
  return (maxHeight - 360).clamp(520.0, 1000.0).toDouble();
}

double hostedSalesCartPanelWidth(double maxWidth) {
  if (hostedSalesUsesCompactLayout(maxWidth)) {
    return double.infinity;
  }
  return maxWidth < 1280 ? 360.0 : 420.0;
}

String hostedShellStateScope(BootstrapConfig config) =>
    '${config.businessId}:${config.shopId}';

BootstrapConfig repairHostedCloudConfig(BootstrapConfig config) {
  if (config.deploymentMode != 'neuradix_cloud') {
    return config;
  }

  final repairedCloudBaseUrl =
      _isLegacyHostedCloudBaseUrl(config.defaultCloudBaseUrl)
          ? _defaultCloudBaseUrl
          : config.defaultCloudBaseUrl;
  final repairedBaseUrl =
      _isLegacyHostedCloudBaseUrl(config.baseUrl)
          ? repairedCloudBaseUrl
          : config.baseUrl;

  if (repairedCloudBaseUrl == config.defaultCloudBaseUrl &&
      repairedBaseUrl == config.baseUrl) {
    return config;
  }

  return config.copyWith(
    baseUrl: repairedBaseUrl,
    useSsl: repairedBaseUrl.startsWith('https://'),
    defaultCloudBaseUrl: repairedCloudBaseUrl,
  );
}

enum _AppStage {
  loading,
  modeChooser,
  instanceSetup,
  login,
  hostedAuth,
  shell,
  hostedShell,
}

bool _usesHostedBackendSync(BootstrapConfig config) =>
    config.syncMode == 'hosted_backend';

String _hostedPlanLabel(String planType) {
  switch (planType) {
    case 'paid_cloud':
      return 'Paid Cloud';
    case 'free_cloud':
      return 'Free Cloud';
    case 'free_local':
    default:
      return 'Free Local';
  }
}

String _formatLocalSyncTimestamp(String? value) {
  final parsed = DateTime.tryParse(value ?? '');
  if (parsed == null) {
    return 'Not yet';
  }
  final local = parsed.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}

class NeuradixPosApp extends StatefulWidget {
  const NeuradixPosApp({super.key, this.database});

  final NeuradixDatabase? database;

  @override
  State<NeuradixPosApp> createState() => _NeuradixPosAppState();
}

class NeuradixInstanceSetupPreview extends StatelessWidget {
  const NeuradixInstanceSetupPreview({
    super.key,
    this.initialUrl = _compiledDefaultInstanceUrl,
    this.errorMessage,
  });

  final String initialUrl;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return _InstanceSetupView(
      initialUrl: initialUrl,
      errorMessage: errorMessage,
      onSave: (_) async {},
      onPreview: () async {},
    );
  }
}

class NeuradixPreviewShellView extends StatelessWidget {
  const NeuradixPreviewShellView({
    required this.controller,
    this.brandName = 'CassarCamilleri POS',
    super.key,
  });

  final PosHomeController controller;
  final String brandName;

  @override
  Widget build(BuildContext context) {
    return _PosShellView(
      controller: controller,
      brandName: brandName,
      onLogout: () async {},
      onEditInstance: () async {},
      onChangePassword: (_) async {},
    );
  }
}

class NeuradixShellHeaderPreview extends StatelessWidget {
  const NeuradixShellHeaderPreview({
    this.brandName = 'CassarCamilleri POS',
    super.key,
  });

  final String brandName;

  @override
  Widget build(BuildContext context) {
    return PosShellHeader(
      brandName: brandName,
      onRefresh: () async {},
      onEditInstance: () async {},
      onLogout: () async {},
    );
  }
}

class NeuradixLeftRailPreview extends StatelessWidget {
  const NeuradixLeftRailPreview({
    super.key,
    this.brandName = 'CassarCamilleri POS',
    this.selectedView = 'Order',
  });

  final String brandName;
  final String selectedView;

  @override
  Widget build(BuildContext context) {
    return _LeftRail(
      brandName: brandName,
      selectedView: selectedView,
      onSelect: (_) {},
    );
  }
}

class NeuradixLoginPreview extends StatelessWidget {
  const NeuradixLoginPreview({
    super.key,
    this.baseUrl = _compiledDefaultInstanceUrl,
    this.brandName = 'CassarCamilleri POS',
    this.busy = false,
    this.errorMessage,
  });

  final String baseUrl;
  final String brandName;
  final bool busy;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return _LoginView(
      baseUrl: baseUrl,
      brandName: brandName,
      busy: busy,
      errorMessage: errorMessage,
      onLogin: ({required String username, required String password}) async {},
      onPreview: () async {},
      onEditInstance: () async {},
      onForgotPassword: (_) async {},
      onShowPrivacyTerms: () async {},
    );
  }
}

class _NeuradixPosAppState extends State<NeuradixPosApp> {
  late final NeuradixDatabase _database;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  BootstrapConfig? _config;
  BootstrapConfigRepository? _bootstrapRepository;
  PosCacheRepository? _cacheRepository;
  HostedLocalRepository? _hostedRepository;
  LocalOrderRepository? _orderRepository;
  LocalSyncRepository? _localSyncRepository;
  LocalSyncCoordinator? _localSyncCoordinator;
  LocalSyncBootstrapResult? _localSyncBootstrapResult;
  String? _localSyncStatusMessage;
  PosBootstrapBundle _bootstrapBundle = PosPreviewData.bootstrap;
  PosHomeController? _controller;
  PosLoginSession? _session;
  _AppStage _stage = _AppStage.loading;
  String? _errorMessage;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _database =
        widget.database ??
        NeuradixDatabase(
          databaseName:
              _dedicatedBenchUrl.isEmpty
                  ? 'neuradix_pos.db'
                  : 'neuradix_ccl_uat.db',
        );
    _initialize();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _database.close();
    super.dispose();
  }

  Future<void> _initialize() async {
    PosHomeController? restoredController;
    try {
      PosDebugLog.info('app.initialize', 'starting startup flow');
      final database = await _database.open().timeout(
        neuradixDatabaseOpenTimeout,
      );
      PosDebugLog.info(
        'app.initialize',
        'database_opened path=${database.path}',
      );
      final bootstrapRepository = BootstrapConfigRepository(database);
      final cacheRepository = PosCacheRepository(database);
      final hostedRepository = HostedLocalRepository(database);
      final orderRepository = LocalOrderRepository(database);
      final localSyncRepository = LocalSyncRepository(database);
      final storedConfig = await bootstrapRepository.read();
      final config =
          storedConfig == null ? null : repairHostedCloudConfig(storedConfig);
      if (storedConfig != null &&
          config != null &&
          !_sameBootstrapConfig(storedConfig, config)) {
        await bootstrapRepository.save(config);
      }
      final session = await cacheRepository.readSession();
      final resolvedStage = _resolveInitialStage(config, session);
      PosDebugLog.info(
        'app.initialize',
        'config=${config?.baseUrl ?? 'none'} '
            'mode=${config?.deploymentMode ?? 'none'} '
            'session=${session?.username ?? 'none'} '
            'stage=$resolvedStage',
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _bootstrapRepository = bootstrapRepository;
        _cacheRepository = cacheRepository;
        _hostedRepository = hostedRepository;
        _orderRepository = orderRepository;
        _localSyncRepository = localSyncRepository;
        _config = config;
        _session = session;
        _bootstrapBundle =
            _bundleFromConfig(config) ?? PosPreviewData.bootstrap;
        _stage = resolvedStage;
        _errorMessage = null;
      });

      if (config != null) {
        PosDebugLog.info('app.initialize', 'refreshing bootstrap theme');
        await _refreshBootstrapTheme(config, silent: true);
      }

      if (config != null &&
          session != null &&
          config.deploymentMode == 'external_backend') {
        PosDebugLog.info(
          'app.initialize',
          'restoring external backend session',
        );
        restoredController = PosHomeController(
          instanceUrl: config.baseUrl,
          bootstrap: _bootstrapBundle,
          session: session,
          cacheRepository: cacheRepository,
          orderRepository: orderRepository,
          apiClient: NeuradixApiClient(
            baseUrl: config.baseUrl,
            apiKey: session.apiKey,
            apiSecret: session.apiSecret,
          ),
          initialCustomers: await cacheRepository
              .searchCustomers('')
              .timeout(const Duration(seconds: 10)),
          initialCatalog: await cacheRepository.readCatalog().timeout(
            const Duration(seconds: 10),
          ),
          initialHistory: await cacheRepository.readHistorySnapshot().timeout(
            const Duration(seconds: 10),
          ),
          initialAccount: await cacheRepository.readAccountSnapshot().timeout(
            const Duration(seconds: 10),
          ),
          initialTaxes: await cacheRepository.readTaxSnapshot().timeout(
            const Duration(seconds: 10),
          ),
        );
        await restoredController.hydrate().timeout(const Duration(seconds: 15));
        if (!mounted) {
          restoredController.dispose();
          return;
        }
        _controller?.dispose();
        setState(() {
          _controller = restoredController;
          _session = session;
          _stage = _AppStage.shell;
          _errorMessage = null;
        });
        PosDebugLog.info(
          'app.initialize',
          'shell restored, launching background sync',
        );
        await restoredController.launchFlow();
        PosDebugLog.info('app.initialize', 'startup flow complete');
        return;
      }

      if (config != null &&
          session != null &&
          config.deploymentMode == 'neuradix_cloud') {
        final localSyncResult = await _prepareLocalSync(
          _config ?? config,
          session,
        );
        final profile = localSyncResult?.profile;
        final syncConfig =
            profile == null
                ? (_config ?? config)
                : (_config ?? config).copyWith(
                  relayUrl: profile.relayUrl,
                  protocolVersion: profile.protocolVersion,
                  shopId: profile.shopId,
                  shopName: profile.shopName,
                );
        if (profile != null) {
          await _bootstrapRepository!.save(syncConfig);
        }
        if (mounted) {
          setState(() {
            _config = syncConfig;
            _localSyncCoordinator = localSyncResult?.coordinator;
            _localSyncBootstrapResult = localSyncResult;
            _localSyncStatusMessage = localSyncResult?.message;
          });
        }
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _stage = _resolveInitialStage(_config, session);
      });
      PosDebugLog.info('app.initialize', 'startup flow complete');
    } on TimeoutException catch (error, stackTrace) {
      restoredController?.dispose();
      _handleStartupFailure(
        'Startup timed out while restoring local POS data. Retry the launch or reset the local browser cache for this app.',
        error,
        stackTrace,
      );
    } catch (error, stackTrace) {
      restoredController?.dispose();
      _handleStartupFailure(
        'Startup failed while restoring the local POS cache. Retry the launch or reset the local browser cache for this app.',
        error,
        stackTrace,
      );
    }
  }

  void _handleStartupFailure(
    String message,
    Object error,
    StackTrace stackTrace,
  ) {
    PosDebugLog.info(
      'app.initialize.error',
      '$message error=$error\n$stackTrace',
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _controller?.dispose();
      _controller = null;
      _busy = false;
      _errorMessage = '$message\n$error';
      _stage = _fallbackStageForStartupFailure(_config);
    });
  }

  _AppStage _fallbackStageForStartupFailure(BootstrapConfig? config) {
    if (config == null) {
      return _AppStage.instanceSetup;
    }
    if (config.deploymentMode == 'neuradix_cloud') {
      return _AppStage.hostedAuth;
    }
    return _AppStage.login;
  }

  Future<void> _retryStartup() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _errorMessage = null;
      _stage = _AppStage.loading;
    });
    await _initialize();
  }

  Future<void> _resetLocalCacheAndRetry() async {
    PosDebugLog.info('app.initialize', 'resetting local cache');
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      await _database.reset();
      _bootstrapRepository = null;
      _cacheRepository = null;
      _hostedRepository = null;
      _orderRepository = null;
      _localSyncRepository = null;
      _localSyncCoordinator = null;
      _localSyncBootstrapResult = null;
      _localSyncStatusMessage = null;
      _config = null;
      _session = null;
      _bootstrapBundle = PosPreviewData.bootstrap;
      _controller?.dispose();
      _controller = null;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _stage = _AppStage.loading;
        });
      }
    }
    await _initialize();
  }

  _AppStage _resolveInitialStage(
    BootstrapConfig? config,
    PosLoginSession? session,
  ) {
    if (config == null) {
      return _dedicatedBenchUrl.isEmpty
          ? _AppStage.modeChooser
          : _AppStage.instanceSetup;
    }
    if (config.deploymentMode == 'neuradix_cloud') {
      return session == null ? _AppStage.hostedAuth : _AppStage.hostedShell;
    }
    return session == null ? _AppStage.login : _AppStage.loading;
  }

  Future<void> _refreshBootstrapTheme(
    BootstrapConfig config, {
    bool silent = false,
  }) async {
    try {
      final api = NeuradixApiClient(baseUrl: config.baseUrl);
      final liveBundle =
          config.deploymentMode == 'neuradix_cloud'
              ? await api.fetchHostedBootstrap()
              : await api.fetchBootstrap();
      final updatedConfig = config.copyWith(
        brandName: liveBundle.brandName,
        supportEmail: liveBundle.supportEmail,
        defaultCloudBaseUrl: liveBundle.defaultCloudBaseUrl,
        relayUrl: liveBundle.relayUrl,
        protocolVersion: liveBundle.protocolVersion,
        featureLocalMultiShopSync:
            liveBundle.features['local_multi_shop_sync'] == true,
        themePrimary: liveBundle.theme.primary,
        themeSecondary: liveBundle.theme.secondary,
        themeAccent: liveBundle.theme.accent,
        themeTextOnPrimary: liveBundle.theme.textOnPrimary,
        themeSurface: liveBundle.theme.surface,
        themeActive: liveBundle.theme.parkOrderButton,
      );
      await _bootstrapRepository!.save(updatedConfig);
      if (!mounted) {
        return;
      }
      setState(() {
        _config = updatedConfig;
        _bootstrapBundle = liveBundle;
        if (!silent) {
          _errorMessage = null;
        }
      });
    } on Exception catch (error) {
      if (!mounted || silent) {
        return;
      }
      setState(() {
        _errorMessage = formatConnectionError(
          error,
          baseUrl: config.baseUrl,
          includePreviewHint: true,
        );
      });
    }
  }

  Future<void> _saveInstanceConfig(String instanceUrl) async {
    final trimmedUrl =
        _dedicatedBenchUrl.isNotEmpty ? _dedicatedBenchUrl : instanceUrl.trim();
    final config = BootstrapConfig(
      baseUrl: trimmedUrl,
      useSsl: trimmedUrl.startsWith('https://'),
      deploymentMode: 'external_backend',
      planType: 'free_local',
      brandName: 'CassarCamilleri POS',
      supportEmail: 'support@neuradix.local',
      defaultCloudBaseUrl: _defaultCloudBaseUrl,
      themePrimary: const PosThemePalette.fallback().primary,
      themeSecondary: const PosThemePalette.fallback().secondary,
      themeAccent: const PosThemePalette.fallback().accent,
      themeTextOnPrimary: const PosThemePalette.fallback().textOnPrimary,
      themeSurface: const PosThemePalette.fallback().surface,
      themeActive: const PosThemePalette.fallback().parkOrderButton,
      deviceId: _config?.deviceId ?? _generateDeviceId(),
      deviceName: _config?.deviceName ?? 'Current Device',
    );

    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    await _bootstrapRepository!.save(config);
    await _refreshBootstrapTheme(config, silent: false);
    final refreshedConfig = await _bootstrapRepository!.read() ?? config;
    if (!mounted) {
      return;
    }
    setState(() {
      _config = refreshedConfig;
      _busy = false;
      _stage = _AppStage.login;
    });
  }

  Future<void> _configureHostedMode() async {
    final existing = _config;
    final config = BootstrapConfig(
      baseUrl: existing?.defaultCloudBaseUrl ?? _defaultCloudBaseUrl,
      useSsl: (existing?.defaultCloudBaseUrl ?? _defaultCloudBaseUrl)
          .startsWith('https://'),
      deploymentMode: 'neuradix_cloud',
      planType: existing?.planType ?? 'free_local',
      brandName: existing?.brandName ?? 'Neuradix POS',
      supportEmail: existing?.supportEmail ?? 'support@neuradix.local',
      defaultCloudBaseUrl:
          existing?.defaultCloudBaseUrl ?? _defaultCloudBaseUrl,
      themePrimary:
          existing?.themePrimary ?? const PosThemePalette.fallback().primary,
      themeSecondary:
          existing?.themeSecondary ??
          const PosThemePalette.fallback().secondary,
      themeAccent:
          existing?.themeAccent ?? const PosThemePalette.fallback().accent,
      themeTextOnPrimary:
          existing?.themeTextOnPrimary ??
          const PosThemePalette.fallback().textOnPrimary,
      themeSurface:
          existing?.themeSurface ?? const PosThemePalette.fallback().surface,
      themeActive:
          existing?.themeActive ??
          const PosThemePalette.fallback().parkOrderButton,
      businessId: existing?.businessId ?? '',
      businessName: existing?.businessName ?? '',
      deviceId:
          ((existing?.deviceId ?? '').isNotEmpty)
              ? (existing?.deviceId ?? '')
              : _generateDeviceId(),
      deviceName:
          ((existing?.deviceName ?? '').isNotEmpty)
              ? (existing?.deviceName ?? '')
              : 'Current Device',
    );
    await _bootstrapRepository!.save(config);
    await _refreshBootstrapTheme(config, silent: true);
    final refreshedConfig = await _bootstrapRepository!.read() ?? config;
    if (!mounted) {
      return;
    }
    setState(() {
      _config = refreshedConfig;
      _stage = _AppStage.hostedAuth;
      _errorMessage = null;
    });
  }

  Future<void> _login({
    required String username,
    required String password,
  }) async {
    if (_busy) {
      return;
    }
    final config = _config;
    if (config == null) {
      return;
    }
    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    try {
      final api = NeuradixApiClient(baseUrl: config.baseUrl);
      final liveBundle = await api.fetchBootstrap();
      final session = await api.login(username: username, password: password);
      final customers = await api.getCustomers(hubManager: session.hubManager);
      final catalog = await api.getCatalog();
      final history = await api.getHistory(hubManager: session.hubManager);
      final account = await api.getAccount(hubManager: session.hubManager);
      final taxes = await api.getTaxes();

      await _cacheRepository!.saveSession(session);
      await _cacheRepository!.replaceCustomers(customers);
      await _cacheRepository!.replaceCatalog(catalog);
      await _cacheRepository!.saveHistorySnapshot(history);
      await _cacheRepository!.saveAccountSnapshot(account);
      await _cacheRepository!.saveTaxSnapshot(taxes);

      final updatedConfig = config.copyWith(
        brandName: liveBundle.brandName,
        themePrimary: liveBundle.theme.primary,
        themeSecondary: liveBundle.theme.secondary,
        themeAccent: liveBundle.theme.accent,
        themeTextOnPrimary: liveBundle.theme.textOnPrimary,
        themeSurface: liveBundle.theme.surface,
        themeActive: liveBundle.theme.parkOrderButton,
      );
      await _bootstrapRepository!.save(updatedConfig);

      final controller = PosHomeController(
        instanceUrl: updatedConfig.baseUrl,
        bootstrap: liveBundle,
        session: session,
        cacheRepository: _cacheRepository!,
        orderRepository: _orderRepository!,
        apiClient: api,
        initialCustomers: customers,
        initialCatalog: catalog,
        initialHistory: history,
        initialAccount: account,
        initialTaxes: taxes,
      );
      await controller.hydrate();

      if (!mounted) {
        return;
      }
      _controller?.dispose();
      setState(() {
        _config = updatedConfig;
        _bootstrapBundle = liveBundle;
        _session = session;
        _controller = controller;
        _stage = _AppStage.shell;
        _busy = false;
      });
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _errorMessage = formatConnectionError(error, baseUrl: config.baseUrl);
      });
    }
  }

  Future<void> _registerHostedBusiness({
    required String businessName,
    required String shopName,
    required String shopCode,
    required String fullName,
    required String email,
    required String password,
    required String planType,
    required String syncMode,
  }) async {
    final config = _config;
    if (config == null) {
      return;
    }
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    final api = NeuradixApiClient(baseUrl: config.baseUrl);
    final attempt = await api.tryRegisterHostedBusiness(
      businessName: businessName,
      fullName: fullName,
      email: email,
      password: password,
      deviceId: config.deviceId,
      deviceName: config.deviceName,
      planType: planType,
      syncMode: syncMode,
      shopName: syncMode == 'local_multi_shop' ? shopName.trim() : '',
      shopCode: syncMode == 'local_multi_shop' ? shopCode.trim() : '',
    );
    if (attempt.auth != null) {
      try {
        await _completeHostedAuthentication(api, attempt.auth!);
      } on Exception catch (error) {
        _showHostedAuthenticationError(error, config.baseUrl);
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _errorMessage = formatConnectionError(
        attempt.error ??
            const NeuradixApiException('Hosted registration failed.'),
        baseUrl: config.baseUrl,
      );
    });
  }

  Future<void> _loginHosted({
    required String email,
    required String password,
  }) async {
    final config = _config;
    if (config == null) {
      return;
    }
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    final api = NeuradixApiClient(baseUrl: config.baseUrl);
    final attempt = await api.tryLoginHosted(
      email: email,
      password: password,
      deviceId: config.deviceId,
      deviceName: config.deviceName,
    );
    if (attempt.auth != null) {
      try {
        await _completeHostedAuthentication(api, attempt.auth!);
      } on Exception catch (error) {
        _showHostedAuthenticationError(error, config.baseUrl);
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _errorMessage = formatConnectionError(
        attempt.error ?? const NeuradixApiException('Hosted login failed.'),
        baseUrl: config.baseUrl,
      );
    });
  }

  Future<void> _completeHostedAuthentication(
    NeuradixApiClient api,
    HostedAuthResult auth,
  ) async {
    PosDebugLog.info(
      'hosted.auth',
      'preparing business=${auth.business.businessId}',
    );
    final businessSwitchError = await _hostedRepository!.prepareForBusiness(
      auth.business.businessId,
    );
    if (businessSwitchError != null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _errorMessage = businessSwitchError;
      });
      return;
    }

    final session = PosLoginSession.fromJson(auth.sessionJson);
    final bootstrap = PosBootstrapBundle.fromPlatform(auth.bootstrapJson);
    PosDebugLog.info(
      'hosted.auth',
      'business prepared sync_mode=${bootstrap.syncMode}',
    );
    var updatedConfig = (_config ?? _emptyHostedConfig()).copyWith(
      baseUrl: _config?.baseUrl ?? _defaultCloudBaseUrl,
      useSsl: (_config?.baseUrl ?? _defaultCloudBaseUrl).startsWith('https://'),
      deploymentMode: 'neuradix_cloud',
      planType: auth.subscriptionPlanType,
      brandName: bootstrap.brandName,
      supportEmail: bootstrap.supportEmail,
      defaultCloudBaseUrl: bootstrap.defaultCloudBaseUrl,
      themePrimary: bootstrap.theme.primary,
      themeSecondary: bootstrap.theme.secondary,
      themeAccent: bootstrap.theme.accent,
      themeTextOnPrimary: bootstrap.theme.textOnPrimary,
      themeSurface: bootstrap.theme.surface,
      themeActive: bootstrap.theme.parkOrderButton,
      businessId: auth.business.businessId,
      businessName: auth.business.businessName,
      syncMode: bootstrap.syncMode,
      relayUrl: bootstrap.relayUrl,
      protocolVersion: bootstrap.protocolVersion,
      metadataOnly: bootstrap.metadataOnly,
      featureLocalMultiShopSync:
          bootstrap.features['local_multi_shop_sync'] == true,
    );

    updatedConfig = await _selectLocalSyncShopForEnrollment(updatedConfig, api);
    PosDebugLog.info(
      'hosted.auth',
      'shop selected shop=${updatedConfig.shopId}',
    );

    final localSyncResult = await _prepareLocalSync(
      updatedConfig,
      session,
      api: api,
    );
    PosDebugLog.info(
      'hosted.auth',
      'local sync prepared status=${localSyncResult?.status ?? 'not_required'}',
    );
    final localSyncProfile = localSyncResult?.profile;
    if (localSyncProfile != null) {
      updatedConfig = updatedConfig.copyWith(
        relayUrl: localSyncProfile.relayUrl,
        protocolVersion: localSyncProfile.protocolVersion,
        shopId: localSyncProfile.shopId,
        shopName: localSyncProfile.shopName,
      );
    }
    await _bootstrapRepository!.save(updatedConfig);
    await _cacheRepository!.saveSession(session);
    await _hostedRepository!.saveBusinessProfile(
      auth.business.copyWith(
        planType: auth.subscriptionPlanType,
        subscriptionStatus: auth.subscriptionStatus,
      ),
    );
    PosDebugLog.info('hosted.auth', 'configuration and session saved');

    if (!mounted) {
      return;
    }
    setState(() {
      _config = updatedConfig;
      _bootstrapBundle = bootstrap;
      _session = session;
      _localSyncCoordinator = localSyncResult?.coordinator;
      _localSyncBootstrapResult = localSyncResult;
      _localSyncStatusMessage = localSyncResult?.message;
      _busy = false;
      _stage = _AppStage.hostedShell;
    });
  }

  void _showHostedAuthenticationError(Object error, String baseUrl) {
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _errorMessage = formatConnectionError(error, baseUrl: baseUrl);
    });
  }

  Future<BootstrapConfig> _selectLocalSyncShopForEnrollment(
    BootstrapConfig config,
    NeuradixApiClient api,
  ) async {
    if (config.syncMode != 'local_multi_shop' ||
        !config.featureLocalMultiShopSync) {
      return config;
    }
    PosDebugLog.info('hosted.auth', 'loading local sync metadata');
    final metadata = LocalSyncMetadata.fromJson(
      await api.getLocalSyncMetadata(),
    );
    PosDebugLog.info(
      'hosted.auth',
      'metadata loaded shops=${metadata.activeShops.length} '
          'devices=${metadata.devices.length}',
    );
    if (metadata.businessId.isNotEmpty &&
        metadata.businessId != config.businessId) {
      throw StateError('The shop metadata belongs to another business.');
    }
    final currentDevice = metadata.device(config.deviceId);
    if (currentDevice != null && currentDevice.isActive) {
      return config.copyWith(
        shopId: currentDevice.shopId,
        shopName: currentDevice.shopName,
      );
    }
    final shops = metadata.activeShops;
    if (shops.isEmpty) {
      throw StateError('No active shop is available for this business.');
    }
    if (!metadata.requiresShopSelectionFor(config.deviceId)) {
      final shop = shops.first;
      return config.copyWith(shopId: shop.shopId, shopName: shop.shopName);
    }
    if (!mounted) {
      throw StateError('Select a shop before enrolling this register.');
    }
    final dialogContext = _navigatorKey.currentContext;
    if (dialogContext == null || !dialogContext.mounted) {
      throw StateError('The shop selector is not ready. Retry login.');
    }
    final selected = await showSelectLocalSyncShopDialog(dialogContext, shops);
    if (selected == null) {
      throw StateError(
        'Select the register shop before starting trusted-device pairing.',
      );
    }
    return config.copyWith(
      shopId: selected.shopId,
      shopName: selected.shopName,
    );
  }

  Future<LocalSyncBootstrapResult?> _prepareLocalSync(
    BootstrapConfig config,
    PosLoginSession session, {
    NeuradixApiClient? api,
  }) async {
    if (config.syncMode != 'local_multi_shop' ||
        !config.featureLocalMultiShopSync) {
      return null;
    }
    final repository = _localSyncRepository;
    if (repository == null || config.businessId.isEmpty) {
      return const LocalSyncBootstrapResult(
        status: 'unavailable',
        message: 'Local multi-shop storage is not ready on this device.',
      );
    }
    final client =
        api ??
        NeuradixApiClient(
          baseUrl: config.baseUrl,
          apiKey: session.apiKey,
          apiSecret: session.apiSecret,
        );
    final bootstrapper = LocalSyncBootstrapper(
      repository: repository,
      keyManager: LocalSyncKeyManager(
        secureStore: FlutterLocalSyncSecureStore(),
      ),
      fetchMetadata: client.getLocalSyncMetadata,
      registerFirstDevice:
          (LocalSyncDeviceKeys keys) => client.registerFirstLocalSyncDevice(
            deviceId: config.deviceId,
            deviceName: config.deviceName,
            signingPublicKey: keys.signingPublicKeyBase64,
            exchangePublicKey: keys.exchangePublicKeyBase64,
            shopId: config.shopId,
            shopName: config.shopName,
          ),
      startEnrollment:
          (LocalSyncEnrollmentKeys keys) => client.startLocalSyncEnrollment(
            deviceId: config.deviceId,
            deviceName: config.deviceName,
            signingPublicKey: keys.signingPublicKeyBase64,
            exchangePublicKey: keys.exchangePublicKeyBase64,
            shopId: config.shopId,
          ),
    );
    try {
      final previousProfile = await repository.readProfile();
      final result = await bootstrapper.bootstrap(
        businessId: config.businessId,
        deviceId: config.deviceId,
        deviceName: config.deviceName,
        fallbackRelayUrl: config.relayUrl,
        fallbackProtocolVersion: config.protocolVersion,
      );
      final currentProfile = result.profile;
      if (previousProfile != null &&
          currentProfile != null &&
          previousProfile.shopId != currentProfile.shopId) {
        await _hostedRepository?.clearInventoryItems();
      }
      return result;
    } on Exception catch (error) {
      return LocalSyncBootstrapResult(
        status: 'unavailable',
        message: 'Local multi-shop setup is unavailable: $error',
      );
    }
  }

  Future<String> _approveLocalSyncPairing(String pairingCode) async {
    final config = _config;
    final session = _session;
    final coordinator = _localSyncCoordinator;
    if (config == null || session == null || coordinator == null) {
      throw StateError('This register is not an active trusted device.');
    }
    final payload = decodeLocalSyncPairingCode(pairingCode);
    if ('${payload['business_id']}' != config.businessId) {
      throw const FormatException(
        'The pairing code belongs to another business.',
      );
    }
    final enrollmentId = '${payload['enrollment_id']}';
    final targetDeviceId = '${payload['device_id']}';
    final encryptedEnvelope = await LocalSyncCrypto()
        .wrapBusinessKeyForEnrollment(
          approverKeys: coordinator.keys,
          businessId: config.businessId,
          enrollmentId: enrollmentId,
          targetDeviceId: targetDeviceId,
          targetExchangePublicKey: base64Decode(
            '${payload['exchange_public_key']}',
          ),
        );
    final api = NeuradixApiClient(
      baseUrl: config.baseUrl,
      apiKey: session.apiKey,
      apiSecret: session.apiSecret,
    );
    await api.approveLocalSyncEnrollment(
      enrollmentId: enrollmentId,
      approverDeviceId: config.deviceId,
      encryptedKeyEnvelope: encryptedEnvelope,
    );
    return 'Register ${payload['device_name'] ?? targetDeviceId} approved.';
  }

  Future<String> _completeLocalSyncPairing() async {
    final config = _config;
    final session = _session;
    final enrollment = _localSyncBootstrapResult;
    if (config == null || session == null || enrollment == null) {
      throw StateError('There is no pending device enrollment.');
    }
    if (enrollment.enrollmentId.isEmpty) {
      throw StateError('The pending enrollment ID is missing.');
    }
    final api = NeuradixApiClient(
      baseUrl: config.baseUrl,
      apiKey: session.apiKey,
      apiSecret: session.apiSecret,
    );
    final completed = await api.completeLocalSyncEnrollment(
      enrollmentId: enrollment.enrollmentId,
      deviceId: config.deviceId,
    );
    final keyManager = LocalSyncKeyManager(
      secureStore: FlutterLocalSyncSecureStore(),
    );
    final pendingKeys = await keyManager.loadEnrollmentKeys(
      businessId: config.businessId,
      deviceId: config.deviceId,
    );
    if (pendingKeys == null) {
      throw StateError('The pending device keys are unavailable.');
    }
    final unwrapped = await LocalSyncCrypto().unwrapBusinessKeyFromEnrollment(
      enrollmentKeys: pendingKeys,
      encryptedEnvelope: '${completed['encrypted_key_envelope'] ?? ''}',
      businessId: config.businessId,
      enrollmentId: enrollment.enrollmentId,
      targetDeviceId: config.deviceId,
    );
    await keyManager.completeEnrollment(
      businessId: config.businessId,
      deviceId: config.deviceId,
      keyEpoch: unwrapped.keyEpoch,
      businessKey: unwrapped.businessKey,
    );
    final localSyncResult = await _prepareLocalSync(config, session, api: api);
    final profile = localSyncResult?.profile;
    final updatedConfig =
        profile == null
            ? config
            : config.copyWith(
              relayUrl: profile.relayUrl,
              protocolVersion: profile.protocolVersion,
              shopId: profile.shopId,
              shopName: profile.shopName,
            );
    await _bootstrapRepository!.save(updatedConfig);
    if (!mounted) {
      return 'Register paired.';
    }
    setState(() {
      _config = updatedConfig;
      _localSyncCoordinator = localSyncResult?.coordinator;
      _localSyncBootstrapResult = localSyncResult;
      _localSyncStatusMessage = localSyncResult?.message;
    });
    return 'Register paired and local multi-shop sync is active.';
  }

  Future<String?> _localSyncShopReassignmentBlockReason(
    int activeCartLines,
  ) async {
    final repository = _localSyncRepository;
    if (repository == null) {
      return 'This register is not ready for shop reassignment.';
    }
    final pendingEvents = await repository.pendingEventCount();
    final parkedOrders = await _orderRepository?.parkedOrderCount() ?? 0;
    final queuedOrders = await _orderRepository?.queuedOrderCount() ?? 0;
    return localSyncShopReassignmentBlockReason(
      pendingEvents: pendingEvents,
      parkedOrders: parkedOrders,
      queuedOrders: queuedOrders,
      activeCartLines: activeCartLines,
    );
  }

  Future<String> _reassignCurrentLocalSyncShop(
    LocalSyncShop targetShop,
    int activeCartLines,
  ) async {
    final config = _config;
    final session = _session;
    final repository = _localSyncRepository;
    final hostedRepository = _hostedRepository;
    if (config == null ||
        session == null ||
        repository == null ||
        hostedRepository == null ||
        _localSyncCoordinator == null) {
      throw StateError('This register is not ready for shop reassignment.');
    }
    if (targetShop.shopId == config.shopId) {
      return 'This register is already assigned to ${targetShop.shopName}.';
    }
    final blockedReason = await _localSyncShopReassignmentBlockReason(
      activeCartLines,
    );
    if (blockedReason != null) {
      throw StateError(blockedReason);
    }

    final api = NeuradixApiClient(
      baseUrl: config.baseUrl,
      apiKey: session.apiKey,
      apiSecret: session.apiSecret,
    );
    await api.assignLocalSyncDeviceShop(
      deviceId: config.deviceId,
      shopId: targetShop.shopId,
    );
    await hostedRepository.clearInventoryItems();
    final previousProfile = _localSyncCoordinator!.profile;
    await repository.saveProfile(
      LocalSyncProfile(
        businessId: previousProfile.businessId,
        shopId: targetShop.shopId,
        shopName: targetShop.shopName,
        deviceId: previousProfile.deviceId,
        deviceName: previousProfile.deviceName,
        relayUrl: previousProfile.relayUrl,
        protocolVersion: previousProfile.protocolVersion,
        keyEpoch: previousProfile.keyEpoch,
        isPreferredPeer: previousProfile.isPreferredPeer,
      ),
    );
    final targetConfig = config.copyWith(
      shopId: targetShop.shopId,
      shopName: targetShop.shopName,
    );
    final result = await _prepareLocalSync(targetConfig, session, api: api);
    final profile = result?.profile;
    final updatedConfig = targetConfig.copyWith(
      relayUrl: profile?.relayUrl ?? targetConfig.relayUrl,
      protocolVersion: profile?.protocolVersion ?? targetConfig.protocolVersion,
      shopId: profile?.shopId ?? targetShop.shopId,
      shopName: profile?.shopName ?? targetShop.shopName,
    );
    await _bootstrapRepository!.save(updatedConfig);
    if (mounted) {
      setState(() {
        _config = updatedConfig;
        _localSyncCoordinator = result?.coordinator;
        _localSyncBootstrapResult = result;
        _localSyncStatusMessage = result?.message;
      });
    }
    return 'Register moved to ${targetShop.shopName}; shop-local inventory was cleared.';
  }

  Future<void> _upgradeHostedPlan() async {
    final config = _config;
    if (config == null || _hostedRepository == null) {
      return;
    }
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final session = await _cacheRepository!.readSession();
      if (session == null) {
        throw const NeuradixApiException('Hosted session is missing.');
      }
      final api = NeuradixApiClient(
        baseUrl: config.baseUrl,
        apiKey: session.apiKey,
        apiSecret: session.apiSecret,
      );
      final upgradedProfile = await api.startUpgrade();
      if (upgradedProfile.syncMode == 'hosted_backend') {
        final inventory = await _hostedRepository!.listInventoryItems();
        final customers = await _hostedRepository!.listCustomers();
        final sales = await _hostedRepository!.listSales();
        final batchPayload = <String, Object?>{
          'inventory_items': inventory
              .map((HostedInventoryItem item) => item.toApiPayload())
              .toList(growable: false),
          'customers': customers
              .map((HostedCustomer customer) => customer.toJson())
              .toList(growable: false),
          'sales': sales
              .map((HostedSaleRecord sale) => sale.toApiPayload())
              .toList(growable: false),
        };
        final batchId = 'upgrade-${DateTime.now().millisecondsSinceEpoch}';
        await _hostedRepository!.saveUpgradeBatch(
          batchId: batchId,
          status: 'submitted',
          payload: batchPayload,
        );
        await api.importLocalBusinessData(
          batchPayload,
          deviceId: config.deviceId,
        );
      }
      final profile = await _hostedRepository!.readBusinessProfile();
      if (profile != null) {
        await _hostedRepository!.saveBusinessProfile(
          profile.copyWith(
            planType: upgradedProfile.planType,
            subscriptionStatus: upgradedProfile.subscriptionStatus,
            planCaps: upgradedProfile.planCaps,
            features: upgradedProfile.features,
            syncMode: upgradedProfile.syncMode,
            metadataOnly: upgradedProfile.metadataOnly,
            relayUrl: upgradedProfile.relayUrl,
            protocolVersion: upgradedProfile.protocolVersion,
          ),
        );
      }
      final updatedConfig = config.copyWith(
        planType: upgradedProfile.planType,
        syncMode: upgradedProfile.syncMode,
        metadataOnly: upgradedProfile.metadataOnly,
        relayUrl: upgradedProfile.relayUrl,
        protocolVersion: upgradedProfile.protocolVersion,
        featureLocalMultiShopSync:
            upgradedProfile.features['local_multi_shop_sync'] == true,
      );
      await _bootstrapRepository!.save(updatedConfig);
      if (!mounted) {
        return;
      }
      setState(() {
        _config = updatedConfig;
        _busy = false;
      });
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _errorMessage = formatConnectionError(error, baseUrl: config.baseUrl);
      });
    }
  }

  Future<void> _enterPreviewMode() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    await _cacheRepository!.replaceCustomers(PosPreviewData.customers);
    await _cacheRepository!.replaceCatalog(PosPreviewData.catalog);
    await _cacheRepository!.saveHistorySnapshot(PosPreviewData.history);
    await _cacheRepository!.saveAccountSnapshot(PosPreviewData.account);

    final controller = PosHomeController(
      instanceUrl: _config?.baseUrl ?? _defaultInstanceUrl,
      bootstrap: PosPreviewData.bootstrap,
      session: PosPreviewData.session,
      cacheRepository: _cacheRepository!,
      orderRepository: _orderRepository!,
      initialCustomers: PosPreviewData.customers,
      initialCatalog: PosPreviewData.catalog,
      initialHistory: PosPreviewData.history,
      initialAccount: PosPreviewData.account,
      initialPolicies: PosPreviewData.policyByCustomer,
    );
    await controller.hydrate();

    if (!mounted) {
      return;
    }
    _controller?.dispose();
    setState(() {
      _bootstrapBundle = PosPreviewData.bootstrap;
      _session = PosPreviewData.session;
      _controller = controller;
      _stage = _AppStage.shell;
      _busy = false;
    });
  }

  Future<void> _logout() async {
    if (_config?.deploymentMode == 'neuradix_cloud') {
      await _cacheRepository?.clearSession();
      if (!mounted) {
        return;
      }
      setState(() {
        _session = null;
        _localSyncCoordinator = null;
        _localSyncBootstrapResult = null;
        _localSyncStatusMessage = null;
        _stage = _AppStage.hostedAuth;
        _errorMessage = null;
      });
      return;
    }
    final controller = _controller;
    if (controller != null) {
      final canLogout = await controller.prepareLogout();
      if (!canLogout) {
        return;
      }
    }
    await _cacheRepository?.clearSession();
    await _cacheRepository?.clearMasterAndTransactionData();
    _controller?.dispose();
    if (!mounted) {
      return;
    }
    setState(() {
      _controller = null;
      _session = null;
      _stage = _AppStage.login;
      _errorMessage = null;
    });
  }

  Future<void> _editInstance() async {
    if (_config?.deploymentMode == 'neuradix_cloud') {
      await _cacheRepository?.clearSession();
      if (!mounted) {
        return;
      }
      setState(() {
        _session = null;
        _stage = _AppStage.modeChooser;
        _errorMessage = null;
      });
      return;
    }
    await _cacheRepository?.clearSession();
    await _cacheRepository?.clearMasterAndTransactionData(keepBootstrap: true);
    _controller?.dispose();
    if (!mounted) {
      return;
    }
    setState(() {
      _controller = null;
      _session = null;
      _stage = _AppStage.instanceSetup;
      _errorMessage = null;
    });
  }

  Future<void> _editInstanceExternalFlow() async {
    await _cacheRepository?.clearSession();
    if (!mounted) {
      return;
    }
    setState(() {
      _controller = null;
      _session = null;
      _stage = _AppStage.instanceSetup;
      _errorMessage = null;
    });
  }

  BootstrapConfig _emptyHostedConfig() {
    return BootstrapConfig(
      baseUrl: _defaultCloudBaseUrl,
      useSsl: _defaultCloudBaseUrl.startsWith('https://'),
      deploymentMode: 'neuradix_cloud',
      planType: 'free_local',
      brandName: 'Neuradix POS',
      supportEmail: 'support@neuradix.local',
      defaultCloudBaseUrl: _defaultCloudBaseUrl,
      themePrimary: const PosThemePalette.fallback().primary,
      themeSecondary: const PosThemePalette.fallback().secondary,
      themeAccent: const PosThemePalette.fallback().accent,
      themeTextOnPrimary: const PosThemePalette.fallback().textOnPrimary,
      themeSurface: const PosThemePalette.fallback().surface,
      themeActive: const PosThemePalette.fallback().parkOrderButton,
      businessId: '',
      businessName: '',
      deviceId: _generateDeviceId(),
      deviceName: 'Current Device',
    );
  }

  String _generateDeviceId() {
    return 'neuradix-device-${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _forgotPassword(String username) async {
    final config = _config;
    if (config == null) {
      return;
    }
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final api = NeuradixApiClient(baseUrl: config.baseUrl);
      final response = await api.forgotPassword(username.trim());
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '${response['message'] ?? 'Password reset requested.'}';
      });
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = formatConnectionError(error, baseUrl: config.baseUrl);
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _showPrivacyTerms() async {
    final config = _config;
    if (config == null) {
      return;
    }
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final api = NeuradixApiClient(baseUrl: config.baseUrl);
      final payload = await api.getPrivacyTerms();
      final dialogContext = _navigatorKey.currentContext;
      if (dialogContext == null || !dialogContext.mounted) {
        return;
      }
      await showDialog<void>(
        context: dialogContext,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Privacy Policy & Terms'),
            content: SizedBox(
              width: 720,
              child: SingleChildScrollView(
                child: SelectableText(
                  'Privacy Policy\n\n${payload['Privacy_Policy'] ?? ''}\n\nTerms & Conditions\n\n${payload['Terms_and_Conditions'] ?? ''}',
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = formatConnectionError(error, baseUrl: config.baseUrl);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _changePassword(String newPassword) async {
    final controller = _controller;
    final config = _config;
    if (controller == null || config == null) {
      return;
    }
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final api = NeuradixApiClient(
        baseUrl: config.baseUrl,
        apiKey: controller.session.apiKey,
        apiSecret: controller.session.apiSecret,
      );
      await api.changePassword(
        username: controller.session.email,
        password: newPassword,
      );
      if (mounted) {
        setState(() {
          _errorMessage = 'Password changed successfully.';
        });
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = formatConnectionError(error, baseUrl: config.baseUrl);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themePalette = PosThemePalette(
      primary: _config?.themePrimary ?? _bootstrapBundle.theme.primary,
      secondary: _config?.themeSecondary ?? _bootstrapBundle.theme.secondary,
      accent: _config?.themeAccent ?? _bootstrapBundle.theme.accent,
      textOnPrimary:
          _config?.themeTextOnPrimary ?? _bootstrapBundle.theme.textOnPrimary,
      surface: _config?.themeSurface ?? _bootstrapBundle.theme.surface,
      textAndCancelIcon: _bootstrapBundle.theme.textAndCancelIcon,
      shadowBorder: _bootstrapBundle.theme.shadowBorder,
      hintText: _bootstrapBundle.theme.hintText,
      fontWhiteColor: _bootstrapBundle.theme.fontWhiteColor,
      parkOrderButton:
          _config?.themeActive ?? _bootstrapBundle.theme.parkOrderButton,
      active: _bootstrapBundle.theme.active,
    );

    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Neuradix POS',
      theme: NeuradixTheme.light(palette: themePalette),
      home: Scaffold(
        body: SafeArea(
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: _buildStageBody()),
              if (_busy)
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Color(0x33000000)),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStageBody() {
    switch (_stage) {
      case _AppStage.loading:
        if (_errorMessage != null) {
          return _StartupRecoveryView(
            message: _errorMessage!,
            onRetry: _retryStartup,
            onResetLocalCache: _resetLocalCacheAndRetry,
          );
        }
        return const Center(child: CircularProgressIndicator());
      case _AppStage.modeChooser:
        return _ModeChooserView(
          onConnectExistingBackend: _editInstanceExternalFlow,
          onUseNeuradixCloud: _configureHostedMode,
          onPreview: _enterPreviewMode,
        );
      case _AppStage.instanceSetup:
        return _InstanceSetupView(
          initialUrl: _config?.baseUrl ?? _defaultInstanceUrl,
          errorMessage: _errorMessage,
          onSave: _saveInstanceConfig,
          onPreview: _enterPreviewMode,
        );
      case _AppStage.login:
        return _LoginView(
          baseUrl: _config?.baseUrl ?? _defaultInstanceUrl,
          brandName: _bootstrapBundle.brandName,
          busy: _busy,
          errorMessage: _errorMessage,
          onLogin: _login,
          onPreview: _enterPreviewMode,
          onEditInstance: _editInstance,
          onForgotPassword: _forgotPassword,
          onShowPrivacyTerms: _showPrivacyTerms,
        );
      case _AppStage.hostedAuth:
        return _HostedAuthView(
          cloudBaseUrl:
              _config?.baseUrl ??
              _config?.defaultCloudBaseUrl ??
              _defaultCloudBaseUrl,
          brandName: _config?.brandName ?? 'Neuradix POS',
          localMultiShopAvailable:
              _config?.featureLocalMultiShopSync == true ||
              _bootstrapBundle.features['local_multi_shop_sync'] == true,
          busy: _busy,
          errorMessage: _errorMessage,
          onRegister: _registerHostedBusiness,
          onLogin: _loginHosted,
          onBack: () async {
            if (!mounted) {
              return;
            }
            setState(() {
              _stage = _AppStage.modeChooser;
              _errorMessage = null;
            });
          },
        );
      case _AppStage.shell:
        return _PosShellView(
          controller: _controller!,
          brandName: _bootstrapBundle.brandName,
          onLogout: _logout,
          onEditInstance: _editInstance,
          onChangePassword: _changePassword,
        );
      case _AppStage.hostedShell:
        return _HostedShellView(
          key: ValueKey<String>(hostedShellStateScope(_config!)),
          config: _config!,
          bootstrap: _bootstrapBundle,
          session: _session!,
          hostedRepository: _hostedRepository!,
          onLogout: _logout,
          onEditMode: _editInstance,
          onUpgrade: _upgradeHostedPlan,
          localSyncCoordinator: _localSyncCoordinator,
          localSyncBootstrapResult: _localSyncBootstrapResult,
          localSyncStatusMessage: _localSyncStatusMessage,
          onApprovePairing: _approveLocalSyncPairing,
          onCompletePairing: _completeLocalSyncPairing,
          onCheckShopReassignment: _localSyncShopReassignmentBlockReason,
          onReassignCurrentShop: _reassignCurrentLocalSyncShop,
        );
    }
  }

  PosBootstrapBundle? _bundleFromConfig(BootstrapConfig? config) {
    if (config == null) {
      return null;
    }
    return PosBootstrapBundle(
      brandName: config.brandName,
      supportEmail: config.supportEmail,
      appName: 'neuradix-pos',
      deploymentMode: config.deploymentMode,
      planType: config.planType,
      syncMode: config.syncMode,
      relayUrl: config.relayUrl,
      protocolVersion: config.protocolVersion,
      metadataOnly: config.metadataOnly,
      defaultCloudBaseUrl: config.defaultCloudBaseUrl,
      priceList: 'Standard Selling',
      offlineHistoryDays: 14,
      offlineSyncCustomerLimit: 10,
      minimumOrderAmount: 50,
      currencySymbol: 'EUR',
      notesBypassMinimum: true,
      theme: PosThemePalette(
        primary: config.themePrimary,
        secondary: config.themeSecondary,
        accent: config.themeAccent,
        textOnPrimary: config.themeTextOnPrimary,
        surface: config.themeSurface,
        textAndCancelIcon: const PosThemePalette.fallback().textAndCancelIcon,
        shadowBorder: const PosThemePalette.fallback().shadowBorder,
        hintText: const PosThemePalette.fallback().hintText,
        fontWhiteColor: const PosThemePalette.fallback().fontWhiteColor,
        parkOrderButton: config.themeActive,
        active: config.themeSurface,
      ),
      features: PosPreviewData.bootstrap.features,
      planCaps: <String, Object?>{
        'plan_type':
            config.deploymentMode == 'neuradix_cloud'
                ? config.planType
                : 'external_backend',
        'sync_mode': config.syncMode,
        'sync_enabled': _usesHostedBackendSync(config),
      },
    );
  }
}

class _StartupRecoveryView extends StatelessWidget {
  const _StartupRecoveryView({
    required this.message,
    required this.onRetry,
    required this.onResetLocalCache,
  });

  final String message;
  final Future<void> Function() onRetry;
  final Future<void> Function() onResetLocalCache;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Neuradix POS could not restore local state',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'The frontend is running, but the saved browser-side cache could not be restored cleanly.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 18),
                  _InlineMessage(
                    message: message,
                    backgroundColor:
                        Theme.of(context).colorScheme.errorContainer,
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: <Widget>[
                      ElevatedButton(
                        onPressed: onRetry,
                        child: const Text('Retry Startup'),
                      ),
                      OutlinedButton(
                        onPressed: onResetLocalCache,
                        child: const Text('Reset Local Cache'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InstanceSetupView extends StatefulWidget {
  const _InstanceSetupView({
    required this.initialUrl,
    required this.onSave,
    required this.onPreview,
    this.errorMessage,
  });

  final String initialUrl;
  final String? errorMessage;
  final Future<void> Function(String instanceUrl) onSave;
  final Future<void> Function() onPreview;

  @override
  State<_InstanceSetupView> createState() => _InstanceSetupViewState();
}

class _InstanceSetupViewState extends State<_InstanceSetupView> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final isCompact = constraints.maxWidth < 900;
        final formCard = Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Connect Neuradix POS',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 12),
                Text(
                  _dedicatedBenchUrl.isNotEmpty
                      ? 'Connect to the CassarCamilleri test server. Customer agreement prices require an online connection.'
                      : 'Enter your dedicated bench URL.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _controller,
                  readOnly: _dedicatedBenchUrl.isNotEmpty,
                  decoration: const InputDecoration(
                    labelText: 'Instance URL',
                    hintText: 'http://neuradix-cassar.localhost:8008',
                  ),
                ),
                const SizedBox(height: 16),
                if (widget.errorMessage != null) ...<Widget>[
                  _InlineMessage(
                    message: widget.errorMessage!,
                    backgroundColor:
                        Theme.of(context).colorScheme.errorContainer,
                  ),
                  const SizedBox(height: 16),
                ],
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    ElevatedButton(
                      onPressed: () => widget.onSave(_controller.text),
                      child: const Text('Save Instance'),
                    ),
                    if (_dedicatedBenchUrl.isEmpty)
                      OutlinedButton(
                        onPressed: widget.onPreview,
                        child: const Text('Preview Tablet UI'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
        final infoCard = Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _dedicatedBenchUrl.isNotEmpty
                      ? 'CassarCamilleri UAT'
                      : 'Neuradix POS',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 18),
                const _BulletLine(
                  text: 'Tablet-first CassarCamilleri navigation and layout',
                ),
                const _BulletLine(
                  text:
                      'Customer-specific catalog refresh and minimum-order rules',
                ),
                const _BulletLine(
                  text:
                      'Park orders locally; review current prices before submission',
                ),
                const _BulletLine(
                  text: 'Customer agreement prices calculated by the server',
                ),
              ],
            ),
          ),
        );

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child:
                  isCompact
                      ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          formCard,
                          const SizedBox(height: 20),
                          infoCard,
                        ],
                      )
                      : Row(
                        children: <Widget>[
                          Expanded(flex: 5, child: formCard),
                          const SizedBox(width: 20),
                          Expanded(flex: 4, child: infoCard),
                        ],
                      ),
            ),
          ),
        );
      },
    );
  }
}

class _LoginView extends StatefulWidget {
  const _LoginView({
    required this.baseUrl,
    required this.brandName,
    required this.busy,
    required this.onLogin,
    required this.onPreview,
    required this.onEditInstance,
    required this.onForgotPassword,
    required this.onShowPrivacyTerms,
    this.errorMessage,
  });

  final String baseUrl;
  final String brandName;
  final bool busy;
  final String? errorMessage;
  final Future<void> Function({
    required String username,
    required String password,
  })
  onLogin;
  final Future<void> Function() onPreview;
  final Future<void> Function() onEditInstance;
  final Future<void> Function(String username) onForgotPassword;
  final Future<void> Function() onShowPrivacyTerms;

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  final _usernameController = TextEditingController(text: _defaultUatUsername);
  final _passwordController = TextEditingController(text: _defaultUatPassword);

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    widget.brandName,
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Sign in to sync customers, pricing, order history, and local offline work with the selected Neuradix bench.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  _DetailPill(label: 'Bench URL', value: widget.baseUrl),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _usernameController,
                    enabled: !widget.busy,
                    decoration: const InputDecoration(labelText: 'Username'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    enabled: !widget.busy,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                  ),
                  const SizedBox(height: 16),
                  if (widget.errorMessage != null) ...<Widget>[
                    _InlineMessage(
                      message: widget.errorMessage!,
                      backgroundColor:
                          Theme.of(context).colorScheme.errorContainer,
                    ),
                    const SizedBox(height: 16),
                  ],
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: <Widget>[
                      ElevatedButton(
                        onPressed:
                            widget.busy
                                ? null
                                : () => widget.onLogin(
                                  username: _usernameController.text,
                                  password: _passwordController.text,
                                ),
                        child: const Text('Sign In'),
                      ),
                      OutlinedButton(
                        onPressed: widget.busy ? null : widget.onPreview,
                        child: const Text('Preview Offline'),
                      ),
                      TextButton(
                        onPressed:
                            widget.busy ? null : () => widget.onEditInstance(),
                        child: const Text('Edit Instance URL'),
                      ),
                      TextButton(
                        onPressed:
                            widget.busy
                                ? null
                                : () => widget.onForgotPassword(
                                  _usernameController.text,
                                ),
                        child: const Text('Forgot Password'),
                      ),
                      TextButton(
                        onPressed:
                            widget.busy
                                ? null
                                : () => widget.onShowPrivacyTerms(),
                        child: const Text('Privacy & Terms'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeChooserView extends StatelessWidget {
  const _ModeChooserView({
    required this.onConnectExistingBackend,
    required this.onUseNeuradixCloud,
    required this.onPreview,
  });

  final Future<void> Function() onConnectExistingBackend;
  final Future<void> Function() onUseNeuradixCloud;
  final Future<void> Function() onPreview;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Start Neuradix POS',
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Choose whether this device connects to an existing Neuradix-compatible backend or runs as a Neuradix cloud business with local-first storage and upgradeable sync.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final compact = constraints.maxWidth < 900;
                  final externalCard = _ModeCard(
                    title: 'Connect Existing Backend',
                    description:
                        'Use a client-owned Neuradix backend such as CassarCamilleri. This keeps the ERP-backed customer, pricing, history, visit-plan, and policy flows.',
                    primaryLabel: 'Enter Backend URL',
                    onPrimary: onConnectExistingBackend,
                    secondaryLabel: 'Preview Tablet UI',
                    onSecondary: onPreview,
                  );
                  final cloudCard = _ModeCard(
                    title: 'Use Neuradix Cloud',
                    description:
                        'Register a hosted Neuradix business. Free Local keeps operations on-device, Free Cloud syncs to the shared Neuradix backend with starter caps, and Paid Cloud is the upgrade path.',
                    primaryLabel: 'Continue To Cloud',
                    onPrimary: onUseNeuradixCloud,
                  );
                  if (compact) {
                    return Column(
                      children: <Widget>[
                        externalCard,
                        const SizedBox(height: 20),
                        cloudCard,
                      ],
                    );
                  }
                  return Row(
                    children: <Widget>[
                      Expanded(child: externalCard),
                      const SizedBox(width: 20),
                      Expanded(child: cloudCard),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.description,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final String description;
  final String primaryLabel;
  final Future<void> Function() onPrimary;
  final String? secondaryLabel;
  final Future<void> Function()? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            Text(description, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                ElevatedButton(
                  onPressed: () => onPrimary(),
                  child: Text(primaryLabel),
                ),
                if (secondaryLabel != null && onSecondary != null)
                  OutlinedButton(
                    onPressed: () => onSecondary!(),
                    child: Text(secondaryLabel!),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class NeuradixHostedAuthPreview extends StatelessWidget {
  const NeuradixHostedAuthPreview({
    super.key,
    this.localMultiShopAvailable = true,
  });

  final bool localMultiShopAvailable;

  @override
  Widget build(BuildContext context) {
    return _HostedAuthView(
      cloudBaseUrl: neuradixDefaultCloudBaseUrlFallback,
      brandName: 'Neuradix POS',
      localMultiShopAvailable: localMultiShopAvailable,
      busy: false,
      onRegister:
          ({
            required String businessName,
            required String shopName,
            required String shopCode,
            required String fullName,
            required String email,
            required String password,
            required String planType,
            required String syncMode,
          }) async {},
      onLogin: ({required String email, required String password}) async {},
      onBack: () async {},
    );
  }
}

class _HostedAuthView extends StatefulWidget {
  const _HostedAuthView({
    required this.cloudBaseUrl,
    required this.brandName,
    required this.localMultiShopAvailable,
    required this.busy,
    required this.onRegister,
    required this.onLogin,
    required this.onBack,
    this.errorMessage,
  });

  final String cloudBaseUrl;
  final String brandName;
  final bool localMultiShopAvailable;
  final bool busy;
  final String? errorMessage;
  final Future<void> Function({
    required String businessName,
    required String shopName,
    required String shopCode,
    required String fullName,
    required String email,
    required String password,
    required String planType,
    required String syncMode,
  })
  onRegister;
  final Future<void> Function({required String email, required String password})
  onLogin;
  final Future<void> Function() onBack;

  @override
  State<_HostedAuthView> createState() => _HostedAuthViewState();
}

class _HostedAuthViewState extends State<_HostedAuthView> {
  bool _registerMode = true;
  String _selectedPlanType = 'free_local';
  String _selectedSyncMode = 'device_local';
  final TextEditingController _businessController = TextEditingController();
  final TextEditingController _shopNameController = TextEditingController();
  final TextEditingController _shopCodeController = TextEditingController();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _businessController.dispose();
    _shopNameController.dispose();
    _shopCodeController.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    widget.brandName,
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _registerMode
                        ? 'Create a Neuradix business. Free Local keeps operational data on one device. Local Multi-Shop shares customers and finalized sales directly between trusted devices without permanent cloud payload storage. Free Cloud stores and syncs operational data on the shared Neuradix backend.'
                        : 'Sign in to your Neuradix cloud business.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 18),
                  _DetailPill(label: 'Cloud URL', value: widget.cloudBaseUrl),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    children: <Widget>[
                      ChoiceChip(
                        label: const Text('Register'),
                        selected: _registerMode,
                        onSelected:
                            widget.busy
                                ? null
                                : (_) => setState(() => _registerMode = true),
                      ),
                      ChoiceChip(
                        label: const Text('Login'),
                        selected: !_registerMode,
                        onSelected:
                            widget.busy
                                ? null
                                : (_) => setState(() => _registerMode = false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (_registerMode) ...<Widget>[
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: <Widget>[
                        ChoiceChip(
                          label: const Text('Free Local'),
                          selected:
                              _selectedPlanType == 'free_local' &&
                              _selectedSyncMode == 'device_local',
                          onSelected:
                              widget.busy
                                  ? null
                                  : (_) => setState(() {
                                    _selectedPlanType = 'free_local';
                                    _selectedSyncMode = 'device_local';
                                  }),
                        ),
                        ChoiceChip(
                          label: Text(
                            widget.localMultiShopAvailable
                                ? 'Local Multi-Shop'
                                : 'Local Multi-Shop (Unavailable)',
                          ),
                          selected: _selectedSyncMode == 'local_multi_shop',
                          onSelected:
                              widget.busy || !widget.localMultiShopAvailable
                                  ? null
                                  : (_) => setState(() {
                                    _selectedPlanType = 'free_local';
                                    _selectedSyncMode = 'local_multi_shop';
                                  }),
                        ),
                        ChoiceChip(
                          label: const Text('Free Cloud'),
                          selected:
                              _selectedPlanType == 'free_cloud' &&
                              _selectedSyncMode == 'hosted_backend',
                          onSelected:
                              widget.busy
                                  ? null
                                  : (_) => setState(() {
                                    _selectedPlanType = 'free_cloud';
                                    _selectedSyncMode = 'hosted_backend';
                                  }),
                        ),
                      ],
                    ),
                    if (_selectedSyncMode == 'local_multi_shop') ...<Widget>[
                      const SizedBox(height: 12),
                      const _InlineMessage(
                        message:
                            'Customers and finalized sales stay on trusted devices. Devices must be online at the same time to exchange encrypted changes; inventory, stock, drafts, and parked carts remain shop-local.',
                        backgroundColor: Color(0xFFEAF2F0),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('hosted-business-name'),
                      controller: _businessController,
                      enabled: !widget.busy,
                      decoration: const InputDecoration(
                        labelText: 'Business Name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_selectedSyncMode == 'local_multi_shop') ...<Widget>[
                      TextField(
                        key: const Key('local-sync-first-shop-name'),
                        controller: _shopNameController,
                        enabled: !widget.busy,
                        decoration: const InputDecoration(
                          labelText: 'First Shop Name',
                          hintText: 'For example, Valletta',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('local-sync-first-shop-code'),
                        controller: _shopCodeController,
                        enabled: !widget.busy,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'First Shop Code',
                          hintText: 'For example, VALLETTA',
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      key: const Key('hosted-owner-full-name'),
                      controller: _fullNameController,
                      enabled: !widget.busy,
                      decoration: const InputDecoration(
                        labelText: 'Owner Full Name',
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    key: const Key('hosted-auth-email'),
                    controller: _emailController,
                    enabled: !widget.busy,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('hosted-auth-password'),
                    controller: _passwordController,
                    enabled: !widget.busy,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                  ),
                  const SizedBox(height: 16),
                  if (widget.errorMessage != null) ...<Widget>[
                    _InlineMessage(
                      message: widget.errorMessage!,
                      backgroundColor:
                          Theme.of(context).colorScheme.errorContainer,
                    ),
                    const SizedBox(height: 16),
                  ],
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: <Widget>[
                      ElevatedButton(
                        key: const Key('hosted-auth-submit'),
                        onPressed:
                            widget.busy
                                ? null
                                : () async {
                                  if (_registerMode) {
                                    await widget.onRegister(
                                      businessName: _businessController.text,
                                      shopName: _shopNameController.text,
                                      shopCode: _shopCodeController.text,
                                      fullName: _fullNameController.text,
                                      email: _emailController.text,
                                      password: _passwordController.text,
                                      planType: _selectedPlanType,
                                      syncMode: _selectedSyncMode,
                                    );
                                  } else {
                                    await widget.onLogin(
                                      email: _emailController.text,
                                      password: _passwordController.text,
                                    );
                                  }
                                },
                        child: Text(
                          _registerMode ? 'Create Business' : 'Sign In',
                        ),
                      ),
                      TextButton(
                        onPressed: widget.busy ? null : () => widget.onBack(),
                        child: const Text('Back'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HostedShellView extends StatefulWidget {
  const _HostedShellView({
    super.key,
    required this.config,
    required this.bootstrap,
    required this.session,
    required this.hostedRepository,
    required this.onLogout,
    required this.onEditMode,
    required this.onUpgrade,
    required this.localSyncCoordinator,
    required this.localSyncBootstrapResult,
    required this.localSyncStatusMessage,
    required this.onApprovePairing,
    required this.onCompletePairing,
    required this.onCheckShopReassignment,
    required this.onReassignCurrentShop,
  });

  final BootstrapConfig config;
  final PosBootstrapBundle bootstrap;
  final PosLoginSession session;
  final HostedLocalRepository hostedRepository;
  final Future<void> Function() onLogout;
  final Future<void> Function() onEditMode;
  final Future<void> Function() onUpgrade;
  final LocalSyncCoordinator? localSyncCoordinator;
  final LocalSyncBootstrapResult? localSyncBootstrapResult;
  final String? localSyncStatusMessage;
  final Future<String> Function(String pairingCode) onApprovePairing;
  final Future<String> Function() onCompletePairing;
  final Future<String?> Function(int activeCartLines) onCheckShopReassignment;
  final Future<String> Function(LocalSyncShop shop, int activeCartLines)
  onReassignCurrentShop;

  @override
  State<_HostedShellView> createState() => _HostedShellViewState();
}

class _HostedInventoryDraft {
  const _HostedInventoryDraft({required this.item, this.imageSelection});

  final HostedInventoryItem item;
  final _HostedImageSelection? imageSelection;
}

class _HostedImageSelection {
  const _HostedImageSelection({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  final String fileName;
  final String mimeType;
  final Uint8List bytes;

  String asDataUri() =>
      hostedImageDataUri(fileName: fileName, bytes: bytes, mimeType: mimeType);
}

class _HostedShellViewState extends State<_HostedShellView>
    with WidgetsBindingObserver {
  static const List<({String label, IconData icon})> _railItems =
      <({String label, IconData icon})>[
        (label: 'Inventory', icon: Icons.inventory_2_outlined),
        (label: 'Customers', icon: Icons.people_outline),
        (label: 'Sales', icon: Icons.point_of_sale_outlined),
        (label: 'History', icon: Icons.history_toggle_off),
        (label: 'My Profile', icon: Icons.account_circle_outlined),
      ];

  late final NeuradixApiClient _apiClient;
  late final TextEditingController _customerSearchController;
  late final TextEditingController _inventorySearchController;
  late final FocusNode _customerSearchFocusNode;
  LocalSyncRelayWorker? _relayWorker;
  LocalSyncRelayStatus _relayStatus = LocalSyncRelayStatus.stopped;
  Timer? _localSyncDiagnosticsTimer;

  HostedBusinessProfile? _profile;
  List<HostedInventoryItem> _inventory = const <HostedInventoryItem>[];
  List<HostedCustomer> _customers = const <HostedCustomer>[];
  List<HostedSaleRecord> _sales = const <HostedSaleRecord>[];
  List<HostedSaleLine> _cart = <HostedSaleLine>[];
  String _selectedView = 'Sales';
  String? _selectedCustomerId;
  bool _busy = false;
  bool _offline = false;
  String? _statusMessage;
  LocalSyncMetadata? _localSyncMetadata;
  int _pendingSyncEvents = 0;
  String? _lastSuccessfulSyncAt;

  HostedCustomer? get _selectedCustomer {
    final customerId = _selectedCustomerId;
    if (customerId == null) {
      return null;
    }
    for (final customer in _customers) {
      if (customer.customerId == customerId) {
        return customer;
      }
    }
    return null;
  }

  List<HostedCustomer> get _customerSearchResults {
    final query =
        _customerSearchFocusNode.hasFocus ? _customerSearchController.text : '';
    return _customers
        .where(
          (HostedCustomer customer) =>
              hostedCustomerMatchesQuery(customer, query),
        )
        .take(query.trim().isEmpty ? 8 : 12)
        .toList(growable: false);
  }

  List<HostedInventoryItem> get _filteredInventory {
    return _inventory
        .where(
          (HostedInventoryItem item) => hostedInventoryMatchesQuery(
            item,
            _inventorySearchController.text,
          ),
        )
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apiClient = NeuradixApiClient(
      baseUrl: widget.config.baseUrl,
      apiKey: widget.session.apiKey,
      apiSecret: widget.session.apiSecret,
    );
    _customerSearchController = TextEditingController();
    _inventorySearchController = TextEditingController();
    _customerSearchFocusNode =
        FocusNode()..addListener(_handleCustomerSearchFocusChange);
    _inventorySearchController.addListener(_handleInventorySearchChange);
    unawaited(_initializeHostedShell());
    if (widget.config.syncMode == 'local_multi_shop') {
      _localSyncDiagnosticsTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => unawaited(_refreshLocalSyncDiagnostics()),
      );
    }
  }

  @override
  void didUpdateWidget(covariant _HostedShellView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.localSyncCoordinator != widget.localSyncCoordinator) {
      unawaited(_configureLocalSyncWorker());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _customerSearchFocusNode
      ..removeListener(_handleCustomerSearchFocusChange)
      ..dispose();
    _customerSearchController.dispose();
    _inventorySearchController
      ..removeListener(_handleInventorySearchChange)
      ..dispose();
    _localSyncDiagnosticsTimer?.cancel();
    unawaited(_relayWorker?.stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_resumeLocalSync());
    }
  }

  Future<void> _resumeLocalSync() async {
    final worker = _relayWorker;
    if (worker == null || !mounted) {
      return;
    }
    try {
      final connected = await worker.reconnectAndFlush();
      if (!mounted) {
        return;
      }
      if (!connected) {
        setState(() {
          _offline = true;
          _statusMessage = localSyncOfflineMessage;
        });
        return;
      }
      await _reloadLocalSyncData();
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _offline = true;
          _statusMessage = formatConnectionError(
            error,
            baseUrl: widget.config.baseUrl,
          );
        });
      }
    }
  }

  Future<void> _initializeHostedShell() async {
    await _hydrate();
    await _refreshLocalSyncDiagnostics(includeMetadata: true);
    await _configureLocalSyncWorker();
  }

  Future<void> _refreshLocalSyncDiagnostics({
    bool includeMetadata = false,
  }) async {
    if (widget.config.syncMode != 'local_multi_shop') {
      return;
    }
    final repository = widget.localSyncCoordinator?.repository;
    try {
      final pending = await repository?.pendingEventCount() ?? 0;
      final lastSuccessful = await repository?.lastSuccessfulSyncAt();
      LocalSyncMetadata? metadata;
      if (includeMetadata || _localSyncMetadata == null) {
        metadata = LocalSyncMetadata.fromJson(
          await _apiClient.getLocalSyncMetadata(),
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingSyncEvents = pending;
        _lastSuccessfulSyncAt = lastSuccessful;
        if (metadata != null) {
          _localSyncMetadata = metadata;
        }
      });
    } on Exception {
      if (!mounted || repository == null) {
        return;
      }
      final pending = await repository.pendingEventCount();
      final lastSuccessful = await repository.lastSuccessfulSyncAt();
      if (mounted) {
        setState(() {
          _pendingSyncEvents = pending;
          _lastSuccessfulSyncAt = lastSuccessful;
        });
      }
    }
  }

  Future<void> _configureLocalSyncWorker() async {
    await _relayWorker?.stop();
    _relayWorker = null;
    final coordinator = widget.localSyncCoordinator;
    if (coordinator == null) {
      if (mounted) {
        setState(() {
          _relayStatus = LocalSyncRelayStatus.stopped;
        });
      }
      return;
    }
    final worker = LocalSyncRelayWorker(
      coordinator: coordinator,
      issueToken:
          () => _apiClient.issueLocalSyncRelayToken(
            deviceId: widget.config.deviceId,
          ),
      refreshMetadata: _apiClient.getLocalSyncMetadata,
      onDataChanged: _reloadLocalSyncData,
      onStatusChanged: (LocalSyncRelayStatus status, String message) {
        if (!mounted) {
          return;
        }
        setState(() {
          _relayStatus = status;
          _offline = status == LocalSyncRelayStatus.offline;
          _statusMessage = message;
        });
        unawaited(_refreshLocalSyncDiagnostics());
      },
    );
    _relayWorker = worker;
    await worker.start();
  }

  Future<void> _reloadLocalSyncData() async {
    final inventory = await widget.hostedRepository.listInventoryItems();
    final customers = await widget.hostedRepository.listCustomers();
    final sales = await widget.hostedRepository.listSales();
    if (!mounted) {
      return;
    }
    setState(() {
      _inventory = inventory;
      _customers = customers;
      _sales = sales;
      _ensureSelectedCustomer(customers);
    });
    await _refreshLocalSyncDiagnostics();
  }

  void _handleCustomerSearchFocusChange() {
    if (!_customerSearchFocusNode.hasFocus) {
      _syncSelectedCustomerLabel();
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _handleInventorySearchChange() {
    if (mounted) {
      setState(() {});
    }
  }

  void _ensureSelectedCustomer(List<HostedCustomer> customers) {
    if (customers.isEmpty) {
      _selectedCustomerId = null;
      if (!_customerSearchFocusNode.hasFocus) {
        _customerSearchController.clear();
      }
      return;
    }
    if (!customers.any(
      (HostedCustomer customer) => customer.customerId == _selectedCustomerId,
    )) {
      _selectedCustomerId = customers.first.customerId;
    }
    _syncSelectedCustomerLabel();
  }

  void _syncSelectedCustomerLabel() {
    if (_customerSearchFocusNode.hasFocus) {
      return;
    }
    final customer = _selectedCustomer;
    if (customer == null) {
      _customerSearchController.clear();
      return;
    }
    final label = hostedCustomerSearchLabel(customer);
    if (_customerSearchController.text == label) {
      return;
    }
    _customerSearchController.value = TextEditingValue(
      text: label,
      selection: TextSelection.collapsed(offset: label.length),
    );
  }

  void _selectCustomer(HostedCustomer customer) {
    final label = hostedCustomerSearchLabel(customer);
    setState(() {
      _selectedCustomerId = customer.customerId;
      _customerSearchController.value = TextEditingValue(
        text: label,
        selection: TextSelection.collapsed(offset: label.length),
      );
    });
    _customerSearchFocusNode.unfocus();
  }

  void _clearCustomerSelection() {
    setState(() {
      _selectedCustomerId = null;
      _customerSearchController.clear();
    });
    _customerSearchFocusNode.requestFocus();
  }

  Future<void> _hydrate() async {
    setState(() {
      _busy = true;
    });
    final profile = await widget.hostedRepository.readBusinessProfile();
    final inventory = await widget.hostedRepository.listInventoryItems();
    final customers = await widget.hostedRepository.listCustomers();
    final sales = await widget.hostedRepository.listSales();
    if (!mounted) {
      return;
    }
    setState(() {
      _profile = profile;
      _inventory = inventory;
      _customers = customers;
      _sales = sales;
      _ensureSelectedCustomer(customers);
      _busy = false;
    });
    if (_usesHostedBackendSync(widget.config)) {
      await _refreshFromCloud(showMessage: false);
    }
  }

  Future<void> _refreshFromCloud({bool showMessage = true}) async {
    if (!_usesHostedBackendSync(widget.config)) {
      if (widget.config.syncMode == 'local_multi_shop' &&
          widget.localSyncCoordinator != null) {
        if (mounted) {
          setState(() {
            _busy = true;
            if (showMessage) {
              _statusMessage = 'Refreshing trusted-register synchronization.';
            }
          });
        }
        try {
          final metadata = await _apiClient.getLocalSyncMetadata();
          await widget.localSyncCoordinator!.refreshTrustedPeers(metadata);
          final worker = _relayWorker;
          if (worker == null || !await worker.reconnectAndFlush()) {
            throw StateError(localSyncOfflineMessage);
          }
          await _reloadLocalSyncData();
          await _refreshLocalSyncDiagnostics(includeMetadata: true);
          if (mounted) {
            setState(() {
              _busy = false;
              _offline = false;
              _statusMessage =
                  worker.onlinePeerCount == 0
                      ? 'Relay reconnected. Open another trusted register to transfer queued changes.'
                      : 'Relay reconnected to ${worker.onlinePeerCount} trusted ${worker.onlinePeerCount == 1 ? 'register' : 'registers'}; queued changes are syncing.';
            });
          }
        } on Exception catch (error) {
          if (mounted) {
            setState(() {
              _busy = false;
              _offline = true;
              _statusMessage = formatConnectionError(
                error,
                baseUrl: widget.config.baseUrl,
              );
            });
          }
        }
      } else if (showMessage && mounted) {
        setState(() {
          _statusMessage =
              widget.config.syncMode == 'local_multi_shop'
                  ? (widget.localSyncStatusMessage ??
                      'Pair this register before using local multi-shop sync.')
                  : 'Device Local mode uses only on-device inventory, customers, and sales data.';
        });
      }
      return;
    }
    setState(() {
      _busy = true;
      if (showMessage) {
        _statusMessage = 'Refreshing inventory, customers, and hosted sales.';
      }
    });
    try {
      await _syncPendingSales();
      final profile = await _apiClient.getCurrentBusiness();
      final customers = await _apiClient.listHostedCustomers();
      final inventory = await _apiClient.listHostedInventoryItems();
      final sales = await _apiClient.getHostedSalesHistory();
      await widget.hostedRepository.saveBusinessProfile(profile);
      await widget.hostedRepository.replaceCustomers(customers);
      await widget.hostedRepository.replaceInventoryItems(inventory);
      await widget.hostedRepository.replaceSubmittedSales(
        sales
            .map(
              (HostedSaleRecord sale) => HostedSaleRecord(
                saleId: sale.saleId,
                remoteSaleId: sale.remoteSaleId,
                customerId: sale.customerId,
                customerName: sale.customerName,
                postingDate: sale.postingDate,
                totalAmount: sale.totalAmount,
                status: 'submitted',
                items: sale.items,
                updatedAt: sale.updatedAt,
              ),
            )
            .toList(growable: false),
      );
      final cachedSales = await widget.hostedRepository.listSales();
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = profile;
        _customers = customers;
        _inventory = inventory;
        _sales = cachedSales;
        _ensureSelectedCustomer(customers);
        _busy = false;
        _offline = false;
        _statusMessage = 'Hosted Neuradix cloud data is up to date.';
      });
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _offline = true;
        _statusMessage = formatConnectionError(
          error,
          baseUrl: widget.config.baseUrl,
        );
      });
    }
  }

  Future<void> _syncPendingSales() async {
    final pendingSales = await widget.hostedRepository.listPendingSales();
    for (final sale in pendingSales) {
      final submitted = await _apiClient.submitHostedSale(
        sale,
        deviceId: widget.config.deviceId,
      );
      await widget.hostedRepository.markSaleSynced(
        saleId: sale.saleId,
        remoteSaleId:
            submitted.remoteSaleId.isNotEmpty
                ? submitted.remoteSaleId
                : submitted.saleId,
      );
    }
  }

  bool _blockUntilLocalSyncPairingCompletes() {
    if (widget.config.syncMode != 'local_multi_shop' ||
        widget.localSyncCoordinator != null) {
      return false;
    }
    setState(() {
      _statusMessage =
          widget.localSyncStatusMessage ??
          'Pair this register before creating local multi-shop data.';
    });
    return true;
  }

  Future<void> _addInventoryItem() async {
    if (_blockUntilLocalSyncPairingCompletes()) {
      return;
    }
    final draft = await _showInventoryDialog(context);
    if (draft == null) {
      return;
    }
    final syncToCloud = _usesHostedBackendSync(widget.config);
    final normalizedItem = normalizeHostedInventoryDraftForSave(
      draft.item,
      syncToCloud: syncToCloud,
    );
    setState(() {
      _busy = true;
    });
    try {
      final imageSelection = draft.imageSelection;
      final localItem =
          imageSelection == null
              ? normalizedItem
              : normalizedItem.copyWith(imageUrl: imageSelection.asDataUri());
      final saved =
          syncToCloud
              ? await _apiClient.upsertHostedInventoryItem(
                normalizedItem,
                imageUploadBase64:
                    imageSelection == null
                        ? null
                        : base64Encode(imageSelection.bytes),
                imageUploadFileName: imageSelection?.fileName,
                imageUploadMimeType: imageSelection?.mimeType,
              )
              : localItem;
      final localSyncCoordinator = widget.localSyncCoordinator;
      if (!syncToCloud && localSyncCoordinator != null) {
        await localSyncCoordinator.saveInventoryItem(saved);
        await _relayWorker?.flushPending();
        await _refreshLocalSyncDiagnostics();
      } else {
        await widget.hostedRepository.upsertInventoryItem(saved);
      }
      final inventory = await widget.hostedRepository.listInventoryItems();
      if (!mounted) {
        return;
      }
      setState(() {
        _inventory = inventory;
        _busy = false;
        _statusMessage =
            syncToCloud
                ? 'Inventory item saved to Neuradix cloud.'
                : localSyncCoordinator != null
                ? 'Inventory item saved for this shop and queued for its registers.'
                : 'Inventory item saved locally on this device.';
      });
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _statusMessage = formatConnectionError(
          error,
          baseUrl: widget.config.baseUrl,
        );
      });
    }
  }

  Future<void> _addCustomer() async {
    if (_blockUntilLocalSyncPairingCompletes()) {
      return;
    }
    final customer = await _showCustomerDialog(context);
    if (customer == null) {
      return;
    }
    final syncToCloud = _usesHostedBackendSync(widget.config);
    final normalizedCustomer = normalizeHostedCustomerDraftForSave(
      customer,
      syncToCloud: syncToCloud,
    );
    setState(() {
      _busy = true;
    });
    try {
      final saved =
          syncToCloud
              ? await _apiClient.upsertHostedCustomer(normalizedCustomer)
              : normalizedCustomer;
      final localSyncCoordinator = widget.localSyncCoordinator;
      if (!syncToCloud && localSyncCoordinator != null) {
        await localSyncCoordinator.saveCustomer(saved);
        await _relayWorker?.flushPending();
        await _refreshLocalSyncDiagnostics();
      } else {
        await widget.hostedRepository.upsertCustomer(saved);
      }
      final customers = await widget.hostedRepository.listCustomers();
      if (!mounted) {
        return;
      }
      setState(() {
        _customers = customers;
        _ensureSelectedCustomer(customers);
        _busy = false;
        _statusMessage =
            syncToCloud
                ? 'Customer saved to Neuradix cloud.'
                : localSyncCoordinator != null
                ? 'Customer saved locally and queued for trusted devices.'
                : 'Customer saved locally on this device.';
      });
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _statusMessage = formatConnectionError(
          error,
          baseUrl: widget.config.baseUrl,
        );
      });
    }
  }

  void _addToCart(HostedInventoryItem item) {
    final index = _cart.indexWhere(
      (HostedSaleLine row) => row.itemId == item.itemId,
    );
    setState(() {
      if (index >= 0) {
        final existing = _cart[index];
        _cart[index] = HostedSaleLine(
          itemId: existing.itemId,
          displayName: existing.displayName,
          qty: existing.qty + 1,
          rate: existing.rate,
          sku: existing.sku,
          barcode: existing.barcode,
          discountAmount: existing.discountAmount,
          taxAmount: existing.taxAmount,
          notes: existing.notes,
        );
      } else {
        _cart = <HostedSaleLine>[
          ..._cart,
          HostedSaleLine(
            itemId: item.itemId,
            displayName: item.displayName,
            qty: 1,
            rate: item.price,
            sku: item.sku,
            barcode: item.barcode,
          ),
        ];
      }
      _statusMessage = '${item.displayName} added to the sale.';
    });
  }

  void _removeFromCart(String itemId) {
    setState(() {
      _cart = _cart
          .where((HostedSaleLine line) => line.itemId != itemId)
          .toList(growable: false);
    });
  }

  void _handleInventorySearchSubmitted(String rawValue) {
    final query = rawValue.trim();
    if (query.isEmpty) {
      return;
    }
    final exactMatch = findHostedInventoryExactMatch(_inventory, query);
    final fallbackMatches = _inventory
        .where(
          (HostedInventoryItem item) =>
              hostedInventoryMatchesQuery(item, query),
        )
        .toList(growable: false);
    final item =
        exactMatch ??
        (fallbackMatches.length == 1 ? fallbackMatches.single : null);
    if (item == null) {
      setState(() {
        _statusMessage =
            'No exact item matched "$query". Keep typing or scan the item barcode again.';
      });
      return;
    }
    _addToCart(item);
    _inventorySearchController.clear();
  }

  Future<void> _submitSale() async {
    if (_blockUntilLocalSyncPairingCompletes()) {
      return;
    }
    final customer = _selectedCustomer;
    if (customer == null) {
      setState(() {
        _statusMessage = 'Create or select a customer before recording a sale.';
      });
      return;
    }
    if (_cart.isEmpty) {
      setState(() {
        _statusMessage =
            'Add at least one inventory item before recording a sale.';
      });
      return;
    }

    final localSale = HostedSaleRecord(
      saleId: 'local-sale-${generateLocalSyncId()}',
      remoteSaleId: '',
      customerId: customer.customerId,
      customerName: customer.displayName,
      postingDate: DateTime.now().toIso8601String().split('T').first,
      totalAmount: _cart.fold<double>(
        0,
        (double total, HostedSaleLine line) => total + line.amount,
      ),
      status: _usesHostedBackendSync(widget.config) ? 'queued' : 'local_only',
      items: _cart,
      updatedAt: DateTime.now().toIso8601String(),
    );

    setState(() {
      _busy = true;
    });
    var savedLocally = false;
    try {
      final localSyncCoordinator = widget.localSyncCoordinator;
      if (!_usesHostedBackendSync(widget.config) &&
          localSyncCoordinator != null) {
        await localSyncCoordinator.saveFinalizedSale(localSale);
        await _relayWorker?.flushPending();
        await _refreshLocalSyncDiagnostics();
      } else {
        await widget.hostedRepository.saveSale(localSale);
      }
      savedLocally = true;
      if (_usesHostedBackendSync(widget.config)) {
        final submitted = await _apiClient.submitHostedSale(
          localSale,
          deviceId: widget.config.deviceId,
        );
        await widget.hostedRepository.markSaleSynced(
          saleId: localSale.saleId,
          remoteSaleId:
              submitted.remoteSaleId.isNotEmpty
                  ? submitted.remoteSaleId
                  : submitted.saleId,
        );
      }
      final sales = await widget.hostedRepository.listSales();
      if (!mounted) {
        return;
      }
      setState(() {
        _sales = sales;
        _cart = <HostedSaleLine>[];
        _busy = false;
        _offline = false;
        _statusMessage =
            _usesHostedBackendSync(widget.config)
                ? 'Sale recorded and synced to Neuradix cloud.'
                : localSyncCoordinator != null
                ? 'Sale recorded locally and queued for trusted devices.'
                : 'Sale recorded locally on this device.';
      });
    } on Exception catch (error) {
      final sales = await widget.hostedRepository.listSales();
      if (!mounted) {
        return;
      }
      setState(() {
        _sales = sales;
        _cart = hostedCartAfterSaleFailure(
          currentCart: _cart,
          savedLocally: savedLocally,
        );
        _busy = false;
        _offline = true;
        _statusMessage =
            savedLocally && _usesHostedBackendSync(widget.config)
                ? 'Sale queued locally because the Neuradix cloud is unreachable.'
                : formatConnectionError(error, baseUrl: widget.config.baseUrl);
      });
    }
  }

  Future<_HostedImageSelection?> _pickHostedImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const NeuradixApiException(
        'The selected image could not be read on this device.',
      );
    }
    final fileName =
        file.name.trim().isEmpty ? 'inventory-image.png' : file.name.trim();
    return _HostedImageSelection(
      fileName: fileName,
      mimeType: hostedImageMimeTypeFromFileName(fileName),
      bytes: bytes,
    );
  }

  Future<void> _showSaleDetailsDialog(HostedSaleRecord sale) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(
            'Sale ${sale.remoteSaleId.isNotEmpty ? sale.remoteSaleId : sale.saleId}',
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _InfoRow(label: 'Customer', value: sale.customerName),
                  _InfoRow(label: 'Posting Date', value: sale.postingDate),
                  _InfoRow(label: 'Status', value: sale.status),
                  _InfoRow(
                    label: 'Total',
                    value: 'EUR ${sale.totalAmount.toStringAsFixed(2)}',
                  ),
                  if (sale.remoteSaleId.isNotEmpty)
                    _InfoRow(label: 'Remote Sale ID', value: sale.remoteSaleId),
                  const SizedBox(height: 8),
                  Text(
                    'Sale Items',
                    style: Theme.of(dialogContext).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  for (final line in sale.items) ...<Widget>[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(line.displayName),
                      subtitle: Text(
                        'Qty ${line.qty.toStringAsFixed(0)} • EUR ${line.rate.toStringAsFixed(2)}'
                        '${line.notes.trim().isEmpty ? '' : ' • ${line.notes.trim()}'}',
                      ),
                      trailing: Text('EUR ${line.amount.toStringAsFixed(2)}'),
                    ),
                    const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHostedHeaderCard(BuildContext context, {required bool compact}) {
    final businessName =
        _profile?.businessName.isNotEmpty == true
            ? _profile!.businessName
            : widget.config.businessName;
    final title =
        businessName.isNotEmpty ? businessName : widget.bootstrap.brandName;
    final pills = Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        _DetailPill(label: 'Business', value: title),
        _DetailPill(
          label: 'Mode',
          value:
              widget.config.syncMode == 'local_multi_shop'
                  ? 'Local Multi-Shop'
                  : _hostedPlanLabel(widget.config.planType),
        ),
        _DetailPill(
          label: 'Sync',
          value:
              widget.config.syncMode == 'local_multi_shop'
                  ? (widget.localSyncCoordinator == null
                      ? 'Pairing Required'
                      : _relayStatus == LocalSyncRelayStatus.connected
                      ? 'Live Relay'
                      : _relayStatus == LocalSyncRelayStatus.connecting
                      ? 'Connecting'
                      : 'Offline / Queued')
                  : (_offline ? 'Offline / Cached' : 'Ready'),
        ),
        if (widget.config.syncMode == 'local_multi_shop')
          _DetailPill(
            label: 'Shop',
            value:
                widget.config.shopName.isEmpty
                    ? 'Pairing Required'
                    : widget.config.shopName,
          ),
        if (widget.config.syncMode == 'local_multi_shop')
          _DetailPill(label: 'Pending', value: '$_pendingSyncEvents'),
        if (widget.config.syncMode == 'local_multi_shop')
          _DetailPill(
            label: 'Last Sync',
            value: _formatLocalSyncTimestamp(_lastSuccessfulSyncAt),
          ),
      ],
    );
    final actions = Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _refreshFromCloud(),
          icon: const Icon(Icons.sync),
          label: const Text('Refresh'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => widget.onEditMode(),
          icon: const Icon(Icons.compare_arrows_outlined),
          label: const Text('Switch Mode'),
        ),
        ElevatedButton.icon(
          onPressed: _busy ? null : () => widget.onLogout(),
          icon: const Icon(Icons.logout_outlined),
          label: const Text('Logout'),
        ),
      ],
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child:
            compact
                ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 14),
                    pills,
                    const SizedBox(height: 14),
                    actions,
                  ],
                )
                : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            title,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 14),
                          pills,
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    actions,
                  ],
                ),
      ),
    );
  }

  Widget _buildHostedCompactNavigation(BuildContext context) {
    return SizedBox(
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _railItems.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (BuildContext context, int index) {
          final item = _railItems[index];
          return SizedBox(
            width: 132,
            child: _RailButton(
              label: item.label,
              icon: item.icon,
              selected: item.label == _selectedView,
              onTap: () {
                setState(() {
                  _selectedView = item.label;
                });
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildHostedInventoryThumbnail(
    HostedInventoryItem item, {
    double size = 52,
  }) {
    final bytes = decodeHostedImageDataUri(item.imageUrl);
    if (bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }

    final resolvedUrl = hostedResolveImageUrl(
      imageUrl: item.imageUrl,
      baseUrl: widget.config.baseUrl,
    );
    if (resolvedUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          resolvedUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder:
              (_, __, ___) => _buildHostedImagePlaceholder(size: size),
        ),
      );
    }
    return _buildHostedImagePlaceholder(size: size);
  }

  Widget _buildHostedImagePlaceholder({double size = 52}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        Icons.image_outlined,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildHostedCustomerSearchField(BuildContext context) {
    final selectedCustomer = _selectedCustomer;
    final searchResults = _customerSearchResults;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: _customerSearchController,
          focusNode: _customerSearchFocusNode,
          enabled: !_busy,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Customer',
            hintText: 'Type customer code or name',
            prefixIcon: const Icon(Icons.search),
            suffixIcon:
                _customerSearchController.text.trim().isEmpty
                    ? null
                    : IconButton(
                      tooltip: 'Clear Selected Customer',
                      onPressed: _busy ? null : _clearCustomerSelection,
                      icon: const Icon(Icons.close),
                    ),
          ),
        ),
        if (_customerSearchFocusNode.hasFocus) ...<Widget>[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color:
                      Theme.of(context).dividerTheme.color ??
                      const Color(0x14000000),
                ),
              ),
              child:
                  searchResults.isEmpty
                      ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No customers match this search.'),
                        ),
                      )
                      : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: searchResults.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (BuildContext context, int index) {
                          final customer = searchResults[index];
                          return ListTile(
                            dense: true,
                            title: Text(customer.displayName),
                            subtitle: Text(
                              [
                                if (customer.customerCode.trim().isNotEmpty)
                                  customer.customerCode.trim(),
                                if (customer.mobileNo.trim().isNotEmpty)
                                  customer.mobileNo.trim(),
                              ].join(' • '),
                            ),
                            onTap:
                                _busy ? null : () => _selectCustomer(customer),
                          );
                        },
                      ),
            ),
          ),
        ],
        if (selectedCustomer != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            'Selected: ${hostedCustomerSearchLabel(selectedCustomer)}'
            '${selectedCustomer.mobileNo.trim().isEmpty ? '' : ' • ${selectedCustomer.mobileNo.trim()}'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final compactShell = constraints.maxWidth < 980;
        final contentCard = Card(
          child: Padding(
            padding: EdgeInsets.all(compactShell ? 16 : 20),
            child: _buildBody(context),
          ),
        );

        if (compactShell) {
          return SafeArea(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              children: <Widget>[
                _buildHostedHeaderCard(context, compact: true),
                const SizedBox(height: 14),
                _buildHostedCompactNavigation(context),
                const SizedBox(height: 14),
                if (_statusMessage != null) ...<Widget>[
                  _InlineMessage(
                    message: _statusMessage!,
                    backgroundColor:
                        _offline
                            ? Theme.of(context).colorScheme.errorContainer
                            : Theme.of(context).colorScheme.secondaryContainer,
                  ),
                  const SizedBox(height: 14),
                ],
                SizedBox(
                  height: hostedCompactBodyHeight(constraints.maxHeight),
                  child: contentCard,
                ),
              ],
            ),
          );
        }

        return Row(
          children: <Widget>[
            _LeftRail(
              brandName:
                  _profile?.businessName.isNotEmpty == true
                      ? _profile!.businessName
                      : widget.bootstrap.brandName,
              selectedView: _selectedView,
              onSelect: (String value) {
                setState(() {
                  _selectedView = value;
                });
              },
              items: _railItems,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                child: Column(
                  children: <Widget>[
                    _buildHostedHeaderCard(context, compact: false),
                    const SizedBox(height: 18),
                    if (_statusMessage != null) ...<Widget>[
                      _InlineMessage(
                        message: _statusMessage!,
                        backgroundColor:
                            _offline
                                ? Theme.of(context).colorScheme.errorContainer
                                : Theme.of(
                                  context,
                                ).colorScheme.secondaryContainer,
                      ),
                      const SizedBox(height: 18),
                    ],
                    Expanded(child: contentCard),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_selectedView) {
      case 'Inventory':
        return _buildInventoryView(context);
      case 'Customers':
        return _buildCustomersView(context);
      case 'History':
        return _buildHistoryView(context);
      case 'My Profile':
        return _buildProfileView(context);
      case 'Sales':
      default:
        return _buildSalesView(context);
    }
  }

  Widget _buildInventoryView(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final compact = constraints.maxWidth < 760;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            compact
                ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Inventory',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _addInventoryItem,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Item'),
                      ),
                    ),
                  ],
                )
                : Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Inventory',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _busy ? null : _addInventoryItem,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Item'),
                    ),
                  ],
                ),
            const SizedBox(height: 16),
            Expanded(
              child:
                  _inventory.isEmpty
                      ? const Center(child: Text('No inventory items yet.'))
                      : ListView.separated(
                        itemCount: _inventory.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (BuildContext context, int index) {
                          final item = _inventory[index];
                          final subtitle = <String>[
                            if (item.sku.trim().isNotEmpty) item.sku.trim(),
                            if (item.barcode.trim().isNotEmpty)
                              'Barcode ${item.barcode.trim()}',
                            'Stock ${item.stockQty.toStringAsFixed(0)}',
                          ].join(' • ');
                          return ListTile(
                            leading: _buildHostedInventoryThumbnail(item),
                            title: Text(item.displayName),
                            subtitle: Text(subtitle),
                            trailing: Text(
                              'EUR ${item.price.toStringAsFixed(2)}',
                            ),
                          );
                        },
                      ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCustomersView(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Customers',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            ElevatedButton.icon(
              onPressed: _busy ? null : _addCustomer,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Add Customer'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child:
              _customers.isEmpty
                  ? const Center(child: Text('No customers yet.'))
                  : ListView.separated(
                    itemCount: _customers.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      final customer = _customers[index];
                      return ListTile(
                        title: Text(customer.displayName),
                        subtitle: Text(
                          [
                            if (customer.customerCode.isNotEmpty)
                              customer.customerCode,
                            if (customer.mobileNo.isNotEmpty) customer.mobileNo,
                            if (customer.emailId.isNotEmpty) customer.emailId,
                          ].join(' • '),
                        ),
                      );
                    },
                  ),
        ),
      ],
    );
  }

  Widget _buildSalesView(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final compact = hostedSalesUsesCompactLayout(constraints.maxWidth);
        final scrollWholePane = hostedSalesUsesScrollableNonCompactPane(
          maxWidth: constraints.maxWidth,
          maxHeight: constraints.maxHeight,
        );
        final embedLists = compact || scrollWholePane;
        final inventoryItems = _filteredInventory;
        final query = _inventorySearchController.text.trim();
        final total = _cart.fold<double>(
          0,
          (double sum, HostedSaleLine line) => sum + line.amount,
        );

        final inventoryList =
            inventoryItems.isEmpty
                ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      query.isEmpty
                          ? 'Add inventory items first.'
                          : 'No items match "$query".',
                    ),
                  ),
                )
                : ListView.separated(
                  shrinkWrap: embedLists,
                  physics:
                      embedLists ? const NeverScrollableScrollPhysics() : null,
                  itemCount: inventoryItems.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final item = inventoryItems[index];
                    final subtitle = <String>[
                      if (item.sku.trim().isNotEmpty) item.sku.trim(),
                      if (item.barcode.trim().isNotEmpty)
                        'Barcode ${item.barcode.trim()}',
                      'Stock ${item.stockQty.toStringAsFixed(0)}',
                    ].join(' • ');
                    return InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: _busy ? null : () => _addToCart(item),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: <Widget>[
                            _buildHostedInventoryThumbnail(item),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    item.displayName,
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(subtitle),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: <Widget>[
                                Text(
                                  'EUR ${item.price.toStringAsFixed(2)}',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 10),
                                FilledButton.icon(
                                  onPressed:
                                      _busy ? null : () => _addToCart(item),
                                  icon: const Icon(
                                    Icons.add_shopping_cart_outlined,
                                  ),
                                  label: Text(compact ? 'Add' : 'Add to Cart'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );

        final inventoryPane = Column(
          mainAxisSize: embedLists ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Inventory', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            TextField(
              controller: _inventorySearchController,
              enabled: !_busy,
              onSubmitted: _handleInventorySearchSubmitted,
              decoration: InputDecoration(
                labelText: 'Search / Scan Item',
                hintText: 'Type name, SKU, or scan barcode',
                prefixIcon: const Icon(Icons.qr_code_scanner_outlined),
                suffixIcon:
                    query.isEmpty
                        ? null
                        : IconButton(
                          onPressed: () {
                            _inventorySearchController.clear();
                          },
                          icon: const Icon(Icons.close),
                        ),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed:
                    _busy
                        ? null
                        : () => _handleInventorySearchSubmitted(
                          _inventorySearchController.text,
                        ),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Add Exact Match'),
              ),
            ),
            const SizedBox(height: 12),
            if (embedLists) inventoryList else Expanded(child: inventoryList),
          ],
        );

        final cartList =
            _cart.isEmpty
                ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('Cart is empty.'),
                  ),
                )
                : ListView.separated(
                  shrinkWrap: embedLists,
                  physics:
                      embedLists ? const NeverScrollableScrollPhysics() : null,
                  itemCount: _cart.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final line = _cart[index];
                    return ListTile(
                      title: Text(line.displayName),
                      subtitle: Text(
                        'Qty ${line.qty.toStringAsFixed(0)} • EUR ${line.rate.toStringAsFixed(2)}',
                      ),
                      trailing: IconButton(
                        onPressed:
                            _busy ? null : () => _removeFromCart(line.itemId),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    );
                  },
                );

        final cartPane = Column(
          mainAxisSize: embedLists ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Sale Composer',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            _buildHostedCustomerSearchField(context),
            const SizedBox(height: 12),
            if (embedLists) cartList else Expanded(child: cartList),
            const SizedBox(height: 12),
            compact
                ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Total: EUR ${total.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _submitSale,
                        child: const Text('Record Sale'),
                      ),
                    ),
                  ],
                )
                : Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Total: EUR ${total.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _busy ? null : _submitSale,
                      child: const Text('Record Sale'),
                    ),
                  ],
                ),
          ],
        );

        if (compact) {
          return ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: <Widget>[
              inventoryPane,
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 18),
              cartPane,
            ],
          );
        }
        if (scrollWholePane) {
          return Row(
            children: <Widget>[
              Expanded(
                flex: 7,
                child: ListView(
                  key: const Key('hosted-sales-inventory-scroll-pane'),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: <Widget>[inventoryPane],
                ),
              ),
              const SizedBox(width: 18),
              SizedBox(
                width: hostedSalesCartPanelWidth(constraints.maxWidth),
                child: ListView(
                  key: const Key('hosted-sales-cart-scroll-pane'),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: <Widget>[cartPane],
                ),
              ),
            ],
          );
        }
        return Row(
          children: <Widget>[
            Expanded(flex: 7, child: inventoryPane),
            const SizedBox(width: 18),
            SizedBox(
              width: hostedSalesCartPanelWidth(constraints.maxWidth),
              child: cartPane,
            ),
          ],
        );
      },
    );
  }

  Widget _buildHistoryView(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('History', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        Expanded(
          child:
              _sales.isEmpty
                  ? const Center(child: Text('No sales recorded yet.'))
                  : ListView.separated(
                    itemCount: _sales.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      final sale = _sales[index];
                      return ListTile(
                        title: Text(sale.customerName),
                        subtitle: Text(
                          '${sale.postingDate} • ${sale.status} • ${sale.items.length} items',
                        ),
                        trailing: Text(
                          'EUR ${sale.totalAmount.toStringAsFixed(2)}',
                        ),
                        onTap: () => _showSaleDetailsDialog(sale),
                      );
                    },
                  ),
        ),
      ],
    );
  }

  Future<void> _showApprovePairingDialog() async {
    final pairingCode = await showLocalSyncPairingApprovalDialog(context);
    if (!mounted) {
      return;
    }
    if (pairingCode == null || pairingCode.trim().isEmpty) {
      return;
    }
    setState(() {
      _busy = true;
      _statusMessage = 'Approving the new trusted register.';
    });
    try {
      final message = await widget.onApprovePairing(pairingCode);
      if (mounted) {
        setState(() {
          _busy = false;
          _statusMessage = message;
        });
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _statusMessage = '$error';
        });
      }
    }
  }

  Future<void> _completePairing() async {
    setState(() {
      _busy = true;
      _statusMessage = 'Completing trusted-register pairing.';
    });
    try {
      final message = await widget.onCompletePairing();
      if (mounted) {
        setState(() {
          _busy = false;
          _statusMessage = message;
        });
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _statusMessage = '$error';
        });
      }
    }
  }

  Future<void> _showCreateLocalSyncShopDialog() async {
    final draft = await showCreateLocalSyncShopDialog(context);
    if (draft == null || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _statusMessage = 'Creating ${draft.name}.';
    });
    try {
      await _apiClient.createLocalSyncShop(
        shopName: draft.name,
        shopCode: draft.code,
      );
      await _refreshLocalSyncDiagnostics(includeMetadata: true);
      if (mounted) {
        setState(() {
          _busy = false;
          _statusMessage = '${draft.name} is ready for register enrollment.';
        });
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _statusMessage = formatConnectionError(
            error,
            baseUrl: widget.config.baseUrl,
          );
        });
      }
    }
  }

  Future<void> _showReassignCurrentShopDialog() async {
    final blockedReason = await widget.onCheckShopReassignment(_cart.length);
    if (!mounted) {
      return;
    }
    if (blockedReason != null) {
      setState(() {
        _statusMessage = blockedReason;
      });
      return;
    }
    final shops = (_localSyncMetadata?.activeShops ?? const <LocalSyncShop>[])
        .where((LocalSyncShop shop) => shop.shopId != widget.config.shopId)
        .toList(growable: false);
    if (shops.isEmpty) {
      setState(() {
        _statusMessage =
            'Create another shop before reassigning this register.';
      });
      return;
    }
    final selected = await showDialog<LocalSyncShop>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Move Register To Another Shop'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 420),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: shops.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final shop = shops[index];
                return ListTile(
                  key: Key('reassign-shop-${shop.shopId}'),
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text(shop.shopName),
                  subtitle: Text(shop.shopCode),
                  onTap: () => Navigator.of(dialogContext).pop(shop),
                );
              },
            ),
          ),
        );
      },
    );
    if (selected == null || !mounted) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Move to ${selected.shopName}?'),
          content: const Text(
            'The current shop catalog and stock will be removed from this register. '
            'Shared customers and finalized sales remain available. Reassignment is '
            'blocked while local work is pending.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep Current Shop'),
            ),
            ElevatedButton(
              key: const Key('confirm-shop-reassignment'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Move Register'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _statusMessage = 'Moving this register to ${selected.shopName}.';
    });
    try {
      final message = await widget.onReassignCurrentShop(
        selected,
        _cart.length,
      );
      if (mounted) {
        setState(() {
          _busy = false;
          _statusMessage = message;
        });
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _statusMessage = '$error';
        });
      }
    }
  }

  Widget _buildProfileView(BuildContext context) {
    final profile = _profile;
    final localSyncBootstrap = widget.localSyncBootstrapResult;
    final pairingCode =
        localSyncBootstrap?.pairingPayload.isNotEmpty == true
            ? encodeLocalSyncPairingCode(localSyncBootstrap!.pairingPayload)
            : '';
    return ListView(
      children: <Widget>[
        Text('My Profile', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        _InfoRow(
          label: 'Business',
          value: profile?.businessName ?? widget.config.businessName,
        ),
        _InfoRow(
          label: 'Plan',
          value: _hostedPlanLabel(widget.config.planType),
        ),
        _InfoRow(
          label: 'Owner',
          value: profile?.ownerUser ?? widget.session.email,
        ),
        _InfoRow(label: 'Device', value: widget.config.deviceName),
        if (widget.config.syncMode == 'local_multi_shop')
          _InfoRow(
            label: 'Shop',
            value:
                widget.config.shopName.isNotEmpty
                    ? widget.config.shopName
                    : 'Pending pairing',
          ),
        if (widget.config.syncMode == 'local_multi_shop')
          _InfoRow(label: 'Register ID', value: widget.config.deviceId),
        if (widget.config.syncMode == 'local_multi_shop')
          _InfoRow(label: 'Relay', value: _relayStatus.name),
        if (widget.config.syncMode == 'local_multi_shop')
          _InfoRow(label: 'Pending Events', value: '$_pendingSyncEvents'),
        if (widget.config.syncMode == 'local_multi_shop')
          _InfoRow(
            label: 'Last Successful Sync',
            value: _formatLocalSyncTimestamp(_lastSuccessfulSyncAt),
          ),
        _InfoRow(label: 'Support', value: widget.bootstrap.supportEmail),
        if ((profile?.planCaps.isNotEmpty ?? false))
          _InfoRow(
            label: 'Plan Caps',
            value: [
              if (profile?.planCaps['max_devices'] != null)
                'Devices ${profile?.planCaps['max_devices']}',
              if (profile?.planCaps['max_items'] != null)
                'Items ${profile?.planCaps['max_items']}',
              if (profile?.planCaps['max_customers'] != null)
                'Customers ${profile?.planCaps['max_customers']}',
              if (profile?.planCaps['max_sales_rows'] != null)
                'Sales ${profile?.planCaps['max_sales_rows']}',
            ].join(' • '),
          ),
        const SizedBox(height: 18),
        if (widget.config.syncMode == 'local_multi_shop' &&
            profile?.membershipRole == 'Owner') ...<Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Shop Management',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              OutlinedButton.icon(
                key: const Key('create-local-sync-shop'),
                onPressed: _busy ? null : _showCreateLocalSyncShopDialog,
                icon: const Icon(Icons.add_business_outlined),
                label: const Text('Add Shop'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Inventory stays within each shop. Customers and finalized sales '
            'synchronize across all trusted shops while devices overlap online.',
          ),
          const SizedBox(height: 12),
          ...(_localSyncMetadata?.activeShops ?? const <LocalSyncShop>[]).map(
            (LocalSyncShop shop) => Card(
              child: ListTile(
                leading: Icon(
                  shop.shopId == widget.config.shopId
                      ? Icons.store
                      : Icons.storefront_outlined,
                ),
                title: Text(shop.shopName),
                subtitle: Text(
                  '${shop.shopCode} • '
                  '${_localSyncMetadata?.devices.where((device) => device.shopId == shop.shopId && device.isActive).length ?? 0} trusted register(s)',
                ),
                trailing:
                    shop.shopId == widget.config.shopId
                        ? const Chip(label: Text('This Register'))
                        : null,
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('reassign-current-register-shop'),
            onPressed:
                _busy || widget.localSyncCoordinator == null
                    ? null
                    : _showReassignCurrentShopDialog,
            icon: const Icon(Icons.move_down_outlined),
            label: const Text('Change This Register Shop'),
          ),
          const SizedBox(height: 18),
          Text(
            'Trusted Registers',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          ...(_localSyncMetadata?.devices ?? const <LocalSyncDeviceSummary>[]).map(
            (LocalSyncDeviceSummary device) => ListTile(
              dense: true,
              leading: Icon(
                device.isActive
                    ? Icons.verified_user_outlined
                    : Icons.phonelink_erase_outlined,
              ),
              title: Text(device.deviceName),
              subtitle: Text(
                '${device.shopName} • ${device.status}'
                '${device.lastSeenOn.isEmpty ? '' : ' • Last seen ${device.lastSeenOn}'}',
              ),
              trailing:
                  device.deviceId == widget.config.deviceId
                      ? const Text('Current')
                      : null,
            ),
          ),
          const SizedBox(height: 18),
        ],
        if (pairingCode.isNotEmpty) ...<Widget>[
          Text(
            'Pair This Register',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter this code on an existing trusted register, approve it, then return here.',
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              pairingCode,
              key: const Key('local-sync-pairing-code'),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            key: const Key('complete-local-sync-pairing'),
            onPressed: _busy ? null : _completePairing,
            icon: const Icon(Icons.verified_user_outlined),
            label: const Text('Complete Pairing'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            key: const Key('copy-local-sync-pairing-code'),
            onPressed:
                _busy
                    ? null
                    : () async {
                      await Clipboard.setData(ClipboardData(text: pairingCode));
                      if (mounted) {
                        setState(() {
                          _statusMessage =
                              'Pairing code copied. Paste it on a trusted register.';
                        });
                      }
                    },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copy Pairing Code'),
          ),
          const SizedBox(height: 18),
        ],
        if (widget.localSyncCoordinator != null) ...<Widget>[
          OutlinedButton.icon(
            key: const Key('approve-local-sync-register'),
            onPressed: _busy ? null : _showApprovePairingDialog,
            icon: const Icon(Icons.phonelink_lock_outlined),
            label: const Text('Approve New Register'),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.config.planType != 'paid_cloud')
          ElevatedButton.icon(
            onPressed:
                _busy
                    ? null
                    : () async {
                      await widget.onUpgrade();
                      await _hydrate();
                    },
            icon: const Icon(Icons.upgrade_outlined),
            label: const Text('Upgrade To Paid Cloud'),
          ),
      ],
    );
  }

  Future<_HostedInventoryDraft?> _showInventoryDialog(
    BuildContext context,
  ) async {
    final skuController = TextEditingController();
    final barcodeController = TextEditingController();
    final nameController = TextEditingController();
    final priceController = TextEditingController(text: '0');
    final stockController = TextEditingController(text: '0');
    _HostedImageSelection? imageSelection;
    String? dialogError;

    return showDialog<_HostedInventoryDraft>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (
            BuildContext context,
            void Function(void Function()) setDialogState,
          ) {
            Future<void> chooseImage() async {
              try {
                final picked = await _pickHostedImage();
                if (picked == null) {
                  return;
                }
                setDialogState(() {
                  imageSelection = picked;
                  dialogError = null;
                });
              } on Exception catch (error) {
                setDialogState(() {
                  dialogError = '$error';
                });
              }
            }

            return AlertDialog(
              title: const Text('Add Inventory Item'),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      InkWell(
                        onTap: chooseImage,
                        borderRadius: BorderRadius.circular(18),
                        child: Ink(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.35),
                            ),
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.04),
                          ),
                          child: Column(
                            children: <Widget>[
                              if (imageSelection != null) ...<Widget>[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.memory(
                                    imageSelection!.bytes,
                                    width: 120,
                                    height: 120,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ] else ...<Widget>[
                                Icon(
                                  Icons.upload_file_outlined,
                                  size: 40,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(height: 10),
                              ],
                              Text(
                                imageSelection?.fileName ??
                                    'Select item image from this device',
                                style: Theme.of(context).textTheme.titleMedium,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                imageSelection == null
                                    ? 'Tap to choose a JPG, PNG, WEBP, or GIF image.'
                                    : 'Tap again to replace the selected image.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (imageSelection != null) ...<Widget>[
                                const SizedBox(height: 10),
                                TextButton.icon(
                                  onPressed: () {
                                    setDialogState(() {
                                      imageSelection = null;
                                    });
                                  },
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Remove Image'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: skuController,
                        decoration: const InputDecoration(labelText: 'SKU'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: barcodeController,
                        decoration: const InputDecoration(
                          labelText: 'Barcode',
                          hintText: 'Scan or type item barcode',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: 'Name'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: 'Price'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: stockController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Stock Qty',
                        ),
                      ),
                      if (dialogError != null) ...<Widget>[
                        const SizedBox(height: 12),
                        _InlineMessage(
                          message: dialogError!,
                          backgroundColor:
                              Theme.of(context).colorScheme.errorContainer,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final itemName = nameController.text.trim();
                    if (itemName.isEmpty) {
                      setDialogState(() {
                        dialogError = 'Enter an item name before saving.';
                      });
                      return;
                    }
                    Navigator.of(dialogContext).pop(
                      _HostedInventoryDraft(
                        item: HostedInventoryItem(
                          itemId: '',
                          sku: skuController.text.trim(),
                          barcode: barcodeController.text.trim(),
                          displayName: itemName,
                          imageUrl: '',
                          price:
                              double.tryParse(priceController.text.trim()) ?? 0,
                          stockQty:
                              double.tryParse(stockController.text.trim()) ?? 0,
                          isActive: true,
                        ),
                        imageSelection: imageSelection,
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<HostedCustomer?> _showCustomerDialog(BuildContext context) async {
    final codeController = TextEditingController();
    final nameController = TextEditingController();
    final mobileController = TextEditingController();
    final emailController = TextEditingController();
    final addressController = TextEditingController();
    return showDialog<HostedCustomer>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Add Customer'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller: codeController,
                    decoration: const InputDecoration(
                      labelText: 'Customer Code',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Customer Name',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: mobileController,
                    decoration: const InputDecoration(labelText: 'Mobile No'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: addressController,
                    decoration: const InputDecoration(labelText: 'Address'),
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(
                  HostedCustomer(
                    customerId: '',
                    customerCode: codeController.text.trim(),
                    displayName: nameController.text.trim(),
                    mobileNo: mobileController.text.trim(),
                    emailId: emailController.text.trim(),
                    primaryAddress: addressController.text.trim(),
                    isActive: true,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 180,
            child: Text(label, style: Theme.of(context).textTheme.titleMedium),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _PosShellView extends StatelessWidget {
  const _PosShellView({
    required this.controller,
    required this.brandName,
    required this.onLogout,
    required this.onEditInstance,
    required this.onChangePassword,
  });

  final PosHomeController controller;
  final String brandName;
  final Future<void> Function() onLogout;
  final Future<void> Function() onEditInstance;
  final Future<void> Function(String newPassword) onChangePassword;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        return Row(
          children: <Widget>[
            if (MediaQuery.sizeOf(context).width >= 700)
              _LeftRail(
                palette: controller.bootstrap.theme,
                brandName: brandName,
                selectedView: controller.selectedView,
                onSelect: controller.selectView,
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                child: Column(
                  children: <Widget>[
                    if (MediaQuery.sizeOf(context).width < 700)
                      DropdownButton<String>(
                        isExpanded: true,
                        value: controller.selectedView,
                        items:
                            [
                                  'Order',
                                  'Customer',
                                  'Plan & Sync',
                                  'History',
                                  'My Profile',
                                ]
                                .map(
                                  (name) => DropdownMenuItem(
                                    value: name,
                                    child: Text(name),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) {
                          if (value != null) controller.selectView(value);
                        },
                      ),
                    PosShellHeader(
                      brandName: brandName,
                      onRefresh: controller.refreshFromBackend,
                      onEditInstance: onEditInstance,
                      onLogout: onLogout,
                    ),
                    const SizedBox(height: 16),
                    if (controller.statusMessage != null) ...<Widget>[
                      _InlineMessage(
                        message: controller.statusMessage!,
                        backgroundColor:
                            controller.isOffline
                                ? const Color(0xFFFFF1D6)
                                : const Color(0xFFE9F7EE),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (controller.isBusy)
                      PosLoadingIndicator(
                        label:
                            controller.isCustomerLoading
                                ? 'Loading customer prices and account…'
                                : 'Fetching prices / syncing data…',
                      ),
                    Expanded(child: _buildSelectedView(context)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSelectedView(BuildContext context) {
    switch (controller.selectedView) {
      case 'Customer':
        return _CustomersView(controller: controller);
      case 'Plan & Sync':
        return _PlanSyncView(controller: controller);
      case 'History':
        return _HistoryView(controller: controller);
      case 'My Profile':
        return _ProfileView(
          controller: controller,
          onLogout: onLogout,
          onChangePassword: onChangePassword,
        );
      case 'Order':
      default:
        return _OrderView(controller: controller);
    }
  }
}

class _LeftRail extends StatelessWidget {
  const _LeftRail({
    required this.brandName,
    required this.selectedView,
    required this.onSelect,
    this.items,
    this.palette = const PosThemePalette.fallback(),
  });

  final String brandName;
  final PosThemePalette palette;
  final String selectedView;
  final ValueChanged<String> onSelect;
  final List<({String label, IconData icon})>? items;

  static const double _railWidth = 132;

  @override
  Widget build(BuildContext context) {
    final railItems =
        items ??
        <({String label, IconData icon})>[
          (label: 'Order', icon: Icons.shopping_bag_outlined),
          (label: 'Customer', icon: Icons.people_outline),
          (label: 'Plan & Sync', icon: Icons.route_outlined),
          (label: 'History', icon: Icons.history_toggle_off),
          (label: 'My Profile', icon: Icons.account_circle_outlined),
        ];

    return Container(
      width: _railWidth,
      color: Colors.white,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color:
                  Theme.of(context).dividerTheme.color ??
                  const Color(0x14000000),
            ),
          ),
        ),
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: SizedBox(
                  height: 92,
                  width: double.infinity,
                  child: Center(
                    child: Text(
                      brandName.isEmpty ? 'Q' : brandName.substring(0, 1),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontSize: 38,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final item in railItems) ...<Widget>[
                      _RailButton(
                        accent: NeuradixTheme.menuAccent(palette, item.label),
                        label: item.label,
                        icon: item.icon,
                        selected: item.label == selectedView,
                        onTap: () => onSelect(item.label),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color:
                        Theme.of(context).dividerTheme.color ??
                        const Color(0x14000000),
                  ),
                ),
                child: SizedBox(
                  height: 44,
                  width: double.infinity,
                  child: Icon(
                    Icons.storefront_outlined,
                    color: Theme.of(
                      context,
                    ).iconTheme.color?.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    this.accent = const Color(0xFF2B6F77),
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final Color accent;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor =
        Theme.of(context).dividerTheme.color ?? const Color(0x14000000);

    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            width: double.infinity,
            constraints: const BoxConstraints.tightFor(height: 108),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: selected ? accent.withValues(alpha: 0.12) : Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected ? accent.withValues(alpha: 0.45) : borderColor,
              ),
              boxShadow:
                  selected
                      ? <BoxShadow>[
                        BoxShadow(
                          color: accent.withValues(alpha: 0.12),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ]
                      : const <BoxShadow>[],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 28, color: accent),
                const SizedBox(height: 10),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: accent,
                    fontSize: 14,
                    height: 1.12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PosShellHeader extends StatelessWidget {
  const PosShellHeader({
    super.key,
    required this.brandName,
    required this.onRefresh,
    required this.onEditInstance,
    required this.onLogout,
  });
  final String brandName;
  final Future<void> Function() onRefresh, onEditInstance, onLogout;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  brandName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Text(
                  'Powered by Neuradix',
                  style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: onRefresh,
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: 'Instance',
            onPressed: onEditInstance,
            icon: const Icon(Icons.settings),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
    ),
  );
}

class CategoryMultiSelect extends StatefulWidget {
  const CategoryMultiSelect({
    super.key,
    required this.categories,
    required this.selected,
    required this.onChanged,
  });
  final List<String> categories;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  @override
  State<CategoryMultiSelect> createState() => _CategoryMultiSelectState();
}

class _CategoryMultiSelectState extends State<CategoryMultiSelect> {
  bool expanded = false;
  String search = '';
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: TextButton.icon(
              onPressed: () => setState(() => expanded = !expanded),
              icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
              label: Text(
                widget.selected.isEmpty
                    ? 'Categories · All'
                    : 'Categories · ${widget.selected.length} selected',
              ),
            ),
          ),
          if (widget.selected.isNotEmpty)
            TextButton(
              onPressed: () => widget.onChanged({}),
              child: const Text('Clear'),
            ),
        ],
      ),
      if (widget.selected.isNotEmpty)
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 80),
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children:
                  widget.selected
                      .map(
                        (category) => InputChip(
                          label: Text(category),
                          onDeleted:
                              () => widget.onChanged(
                                {...widget.selected}..remove(category),
                              ),
                        ),
                      )
                      .toList(),
            ),
          ),
        ),
      if (expanded) ...[
        TextField(
          onChanged: (value) => setState(() => search = value),
          decoration: const InputDecoration(
            hintText: 'Search categories',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 140,
          child: Builder(
            builder: (context) {
              final matches =
                  widget.categories
                      .where(
                        (name) => name.toLowerCase().contains(
                          search.trim().toLowerCase(),
                        ),
                      )
                      .toList();
              return matches.isEmpty
                  ? const Center(child: Text('No matching categories'))
                  : ListView(
                    children:
                        matches
                            .map(
                              (name) => CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(name),
                                value: widget.selected.contains(name),
                                onChanged: (checked) {
                                  final selection = {...widget.selected};
                                  checked == true
                                      ? selection.add(name)
                                      : selection.remove(name);
                                  widget.onChanged(selection);
                                },
                              ),
                            )
                            .toList(),
                  );
            },
          ),
        ),
      ],
    ],
  );
}

/// Keeps the cart reachable while browsing on phones and short emulator screens.
class CompactOrderWorkspace extends StatelessWidget {
  const CompactOrderWorkspace({
    super.key,
    required this.catalog,
    required this.cart,
    required this.cartLabel,
  });
  final Widget catalog;
  final Widget cart;
  final String cartLabel;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(child: catalog),
      SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.shopping_cart_outlined),
            label: Text(cartLabel),
            onPressed:
                () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder:
                      (context) => SafeArea(
                        child: SizedBox(
                          height: MediaQuery.sizeOf(context).height * .9,
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Text('Cart'),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Close cart',
                                    onPressed: () => Navigator.pop(context),
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                              Expanded(
                                child: SingleChildScrollView(child: cart),
                              ),
                            ],
                          ),
                        ),
                      ),
                ),
          ),
        ),
      ),
    ],
  );
}

class PosLoadingIndicator extends StatelessWidget {
  const PosLoadingIndicator({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Column(
      children: [
        const LinearProgressIndicator(),
        Padding(padding: const EdgeInsets.all(8), child: Text(label)),
      ],
    ),
  );
}

class _OrderView extends StatefulWidget {
  const _OrderView({required this.controller});

  final PosHomeController controller;

  @override
  State<_OrderView> createState() => _OrderViewState();
}

class _OrderViewState extends State<_OrderView> {
  late final TextEditingController _searchController;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: widget.controller.catalogSearch,
    );
    _notesController = TextEditingController(
      text: widget.controller.orderNotes,
    );
  }

  @override
  void didUpdateWidget(covariant _OrderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_notesController.text != widget.controller.orderNotes) {
      _notesController.text = widget.controller.orderNotes;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final isCompact = posOrderUsesCompactLayout(
          constraints.maxWidth,
          maxHeight: constraints.maxHeight,
        );
        final cartPanelWidth =
            isCompact
                ? double.infinity
                : posOrderCartPanelWidth(constraints.maxWidth);
        final catalogColumn = Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: controller.updateCatalogSearch,
                      decoration: const InputDecoration(
                        hintText: 'Search products / category',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: constraints.maxWidth < 700 ? 140 : 250,
                    child: _SelectedCustomerBanner(controller: controller),
                  ),
                ],
              ),
            ),
            CategoryMultiSelect(
              categories: controller.allCategories,
              selected: controller.selectedCategories,
              onChanged: controller.setCategories,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _SectionCard(
                child:
                    controller.catalogGroups.isEmpty
                        ? const Center(child: Text('No items found'))
                        : ListView(
                          children: controller.catalogGroups
                              .map(
                                (PosCatalogGroup group) => _CatalogGroupSection(
                                  group: group,
                                  instanceUrl: controller.instanceUrl,
                                  onAddItem: controller.addItem,
                                  searchResults:
                                      controller.catalogSearch
                                          .trim()
                                          .isNotEmpty,
                                ),
                              )
                              .toList(growable: false),
                        ),
              ),
            ),
          ],
        );
        final cartPanel = SizedBox(
          width: cartPanelWidth,
          child: _CartPanel(
            controller: controller,
            notesController: _notesController,
            compact: isCompact,
          ),
        );

        if (isCompact) {
          return CompactOrderWorkspace(
            catalog: catalogColumn,
            cartLabel:
                'View cart (${controller.cartLines.length}) · ${controller.grandTotal.toStringAsFixed(2)}',
            cart: AnimatedBuilder(
              animation: controller,
              builder:
                  (context, _) => _CartPanel(
                    controller: controller,
                    notesController: _notesController,
                    compact: true,
                  ),
            ),
          );
        }
        return Row(
          children: <Widget>[
            Expanded(flex: 7, child: catalogColumn),
            const SizedBox(width: 16),
            cartPanel,
          ],
        );
      },
    );
  }
}

class _SelectedCustomerBanner extends StatelessWidget {
  const _SelectedCustomerBanner({required this.controller});

  final PosHomeController controller;

  @override
  Widget build(BuildContext context) {
    final customer = controller.selectedCustomer;
    final policy = controller.selectedPolicy;
    final issueStatement = controller.selectedIssueStatement;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          onPressed: () => controller.selectView('Customer'),
          icon: const Icon(Icons.people_outline, size: 18),
          label: Text(
            customer?.displayName ?? 'Choose Customer',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (policy != null && (policy.isFrozen || policy.minimumOrderRequired))
          Text(
            policy.isFrozen
                ? 'Frozen account'
                : 'Minimum ${policy.minimumOrderAmount.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        if (issueStatement != null)
          InkWell(
            onTap: () => _showIssueStatement(context, issueStatement),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Text('Account details'),
            ),
          ),
      ],
    );
  }

  Future<void> _showIssueStatement(
    BuildContext context,
    PosIssueStatement issueStatement,
  ) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Issue Statement'),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Outstanding ${issueStatement.balance.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  if (issueStatement.primaryAddress.isNotEmpty)
                    Text(issueStatement.primaryAddress),
                  if (issueStatement.vat.isNotEmpty)
                    Text('VAT ${issueStatement.vat}'),
                  if (issueStatement.paymentTerm.isNotEmpty)
                    Text('Payment Term ${issueStatement.paymentTerm}'),
                  const SizedBox(height: 16),
                  for (final row in issueStatement.rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  row.invoiceId,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                Text('${row.invoiceDate} • Due ${row.dueDate}'),
                              ],
                            ),
                          ),
                          Text(
                            '${row.totalRowBalance.toStringAsFixed(2)} ${row.currency}',
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

class _CatalogGroupSection extends StatelessWidget {
  const _CatalogGroupSection({
    required this.group,
    required this.instanceUrl,
    required this.onAddItem,
    this.searchResults = false,
  });
  final PosCatalogGroup group;
  final String instanceUrl;
  final ValueChanged<PosCatalogItem> onAddItem;
  final bool searchResults;
  @override
  Widget build(BuildContext context) => CatalogCategoryShelf(
    group: group,
    instanceUrl: instanceUrl,
    onAddItem: onAddItem,
    searchResults: searchResults,
  );
}

class CatalogCategoryShelf extends StatelessWidget {
  const CatalogCategoryShelf({
    super.key,
    required this.group,
    required this.instanceUrl,
    required this.onAddItem,
    this.searchResults = false,
  });
  final PosCatalogGroup group;
  final String instanceUrl;
  final ValueChanged<PosCatalogItem> onAddItem;
  final bool searchResults;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                group.groupName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (!searchResults) const Icon(Icons.swipe, size: 18),
          ],
        ),
        const SizedBox(height: 8),
        if (searchResults)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in group.items)
                _CatalogItemCard(
                  item: item,
                  instanceUrl: instanceUrl,
                  onAddItem: onAddItem,
                ),
            ],
          )
        else
          SizedBox(
            height: MediaQuery.sizeOf(context).width >= 1000 ? 480 : 236,
            child: GridView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: group.items.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount:
                    MediaQuery.sizeOf(context).width >= 1000 ? 2 : 1,
                mainAxisExtent: 190,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemBuilder:
                  (context, index) => _CatalogItemCard(
                    item: group.items[index],
                    instanceUrl: instanceUrl,
                    onAddItem: onAddItem,
                  ),
            ),
          ),
      ],
    ),
  );
}

Future<void> showCatalogItemPreview(
  BuildContext context,
  PosCatalogItem item,
  String instanceUrl,
  ValueChanged<PosCatalogItem> onAdd,
) => showDialog<void>(
  context: context,
  builder: (context) {
    final image = buildCatalogImageProvider(
      instanceUrl: instanceUrl,
      item: item,
    );
    return AlertDialog(
      title: Text(item.displayName),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 220,
                width: double.infinity,
                child:
                    image == null
                        ? const Icon(Icons.local_offer_outlined, size: 80)
                        : Image(
                          image: image,
                          fit: BoxFit.contain,
                          errorBuilder:
                              (_, __, ___) => const Icon(
                                Icons.image_not_supported_outlined,
                                size: 80,
                              ),
                        ),
              ),
              const SizedBox(height: 16),
              Text(item.itemCode),
              Text('${item.stockQty.toStringAsFixed(0)} in stock'),
              Text(
                item.pricingAvailable
                    ? '${item.price.toStringAsFixed(2)} per ${item.defaultUom}'
                    : 'Price unavailable',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            onAdd(item);
          },
          child: const Text('Add to cart'),
        ),
      ],
    );
  },
);

class _CatalogItemCard extends StatelessWidget {
  const _CatalogItemCard({
    required this.item,
    required this.instanceUrl,
    required this.onAddItem,
  });

  final PosCatalogItem item;
  final String instanceUrl;
  final ValueChanged<PosCatalogItem> onAddItem;

  @override
  Widget build(BuildContext context) {
    final imageProvider = buildCatalogImageProvider(
      instanceUrl: instanceUrl,
      item: item,
    );
    return SizedBox(
      width: 182,
      child: Card(
        child: InkWell(
          onTap: () => onAddItem(item),
          onLongPress:
              () =>
                  showCatalogItemPreview(context, item, instanceUrl, onAddItem),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  height: 54,
                  width: 54,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child:
                      imageProvider == null
                          ? Icon(
                            Icons.local_offer_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          )
                          : Image(
                            image: imageProvider,
                            fit: BoxFit.cover,
                            errorBuilder:
                                (_, __, ___) => Icon(
                                  Icons.local_offer_outlined,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                          ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  '${item.stockQty.toStringAsFixed(0)} in stock',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        item.pricingAvailable
                            ? item.price.toStringAsFixed(2)
                            : 'Price unavailable',
                        style: Theme.of(
                          context,
                        ).textTheme.headlineMedium?.copyWith(fontSize: 20),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Product details',
                      onPressed:
                          () => showCatalogItemPreview(
                            context,
                            item,
                            instanceUrl,
                            onAddItem,
                          ),
                      icon: const Icon(Icons.info_outline, size: 18),
                    ),
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: Icon(
                        Icons.add,
                        size: 18,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({
    required this.controller,
    required this.notesController,
    required this.compact,
  });

  final PosHomeController controller;
  final TextEditingController notesController;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final policy = controller.selectedPolicy;
    return Column(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: <Widget>[
        if (controller.isBusy)
          const PosLoadingIndicator(label: 'Updating cart prices…'),
        compact
            ? SizedBox(
              height: 560,
              child: _buildOrderCard(context, policy, false),
            )
            : Expanded(child: _buildOrderCard(context, policy, true)),
        const SizedBox(height: 14),
        SizedBox(
          height: compact ? 240 : 150,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Parked Orders',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      _Badge(
                        label: '${controller.parkedOrders.length}',
                        tone: _BadgeTone.neutral,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child:
                        controller.parkedOrders.isEmpty
                            ? const Center(
                              child: Text('No parked orders on this device'),
                            )
                            : ListView.builder(
                              itemCount: controller.parkedOrders.length,
                              itemBuilder: (BuildContext context, int index) {
                                final order = controller.parkedOrders[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Text(
                                              order.customerId,
                                              style:
                                                  Theme.of(
                                                    context,
                                                  ).textTheme.titleLarge,
                                            ),
                                            Text(
                                              order.updatedAtIso
                                                  .split('T')
                                                  .first,
                                              style:
                                                  Theme.of(
                                                    context,
                                                  ).textTheme.bodyMedium,
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        onPressed:
                                            () => controller.loadParkedOrder(
                                              order,
                                            ),
                                        icon: const Icon(
                                          Icons.playlist_add_check,
                                        ),
                                      ),
                                      IconButton(
                                        onPressed:
                                            () => controller.discardParkedOrder(
                                              order.clientOrderId,
                                            ),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderCard(
    BuildContext context,
    PosCustomerPolicy? policy,
    bool expandList,
  ) {
    final list =
        controller.cartLines.isEmpty
            ? const Center(child: Text('Select products to start the order'))
            : ListView.separated(
              itemCount: controller.cartLines.length,
              separatorBuilder: (_, __) => const Divider(height: 18),
              itemBuilder: (BuildContext context, int index) {
                final line = controller.cartLines[index];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            line.displayName,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            controller.hasCurrentPrices
                                ? '${line.price.toStringAsFixed(2)} per ${line.uom}'
                                : 'Awaiting customer prices',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          if (line.notes.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Note: ${line.notes}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _showLineNotesDialog(context, line),
                      icon: const Icon(Icons.sticky_note_2_outlined),
                    ),
                    _QuantityEditor(
                      qty: line.qty,
                      onDecrease: () => controller.changeLineQuantity(line, -1),
                      onIncrease: () => controller.changeLineQuantity(line, 1),
                    ),
                  ],
                );
              },
            );

    return Card(
      child: Padding(
        padding: EdgeInsets.all(expandList ? 14 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Order', style: Theme.of(context).textTheme.headlineMedium),
            SizedBox(height: expandList ? 6 : 8),
            Text(
              controller.selectedCustomer?.displayName ??
                  'Waiting for customer',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (policy != null &&
                (policy.hasOutstandingDocuments ||
                    policy.isFrozen)) ...<Widget>[
              const SizedBox(height: 12),
              _InlineMessage(
                message:
                    policy.isFrozen
                        ? 'Frozen customer. Orders are blocked until the account is cleared.'
                        : 'Issue statement balance ${policy.outstandingAmount.toStringAsFixed(2)} is still open.',
                backgroundColor:
                    policy.isFrozen
                        ? Theme.of(context).colorScheme.errorContainer
                        : const Color(0xFFFFF1D6),
              ),
            ],
            SizedBox(height: expandList ? 12 : 16),
            expandList
                ? Expanded(child: list)
                : SizedBox(height: 180, child: list),
            TextField(
              controller: notesController,
              minLines: 1,
              maxLines: expandList ? 1 : 2,
              onChanged: controller.setOrderNotes,
              decoration: const InputDecoration(
                labelText: 'Notes',
                hintText: 'General order notes',
              ),
            ),
            SizedBox(height: expandList ? 10 : 14),
            _SummaryRow(label: 'Subtotal', value: controller.subtotal),
            _SummaryRow(label: 'Taxes', value: controller.taxTotal),
            _SummaryRow(
              label: 'Grand Total',
              value: controller.grandTotal,
              emphasized: true,
            ),
            SizedBox(height: expandList ? 10 : 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: controller.parkCurrentOrder,
                    child: const Text('Park Order'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: controller.submitCurrentOrder,
                    child: const Text('Submit Order'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLineNotesDialog(BuildContext context, CartLine line) {
    final controller = TextEditingController(text: line.notes);
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Item Note • ${line.displayName}'),
          content: TextField(
            controller: controller,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Line note',
              hintText: 'Used for minimum-order bypass and order context',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                this.controller.setLineNotes(line, controller.text);
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}

class _CustomersView extends StatefulWidget {
  const _CustomersView({required this.controller});

  final PosHomeController controller;

  @override
  State<_CustomersView> createState() => _CustomersViewState();
}

class _CustomersViewState extends State<_CustomersView> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: widget.controller.customerSearch,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Column(
      children: <Widget>[
        _SectionCard(
          child:
              MediaQuery.sizeOf(context).width < 700
                  ? Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        onChanged: controller.updateCustomerSearch,
                        decoration: const InputDecoration(
                          hintText: 'Search customers',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed:
                                () => _showCreateCustomerDialog(
                                  context,
                                  controller,
                                ),
                            child: const Text('Create Customer'),
                          ),
                          TextButton(
                            onPressed:
                                () => _showLookupCustomerDialog(
                                  context,
                                  controller,
                                ),
                            child: const Text('Lookup Mobile'),
                          ),
                        ],
                      ),
                    ],
                  )
                  : Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Customers',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _searchController,
                          onChanged: controller.updateCustomerSearch,
                          decoration: const InputDecoration(
                            hintText: 'Enter customer name',
                            prefixIcon: Icon(Icons.search),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed:
                            () =>
                                _showCreateCustomerDialog(context, controller),
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('Create Customer'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed:
                            () =>
                                _showLookupCustomerDialog(context, controller),
                        icon: const Icon(Icons.search_off_outlined),
                        label: const Text('Lookup Mobile'),
                      ),
                    ],
                  ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _SectionCard(
            child:
                controller.customers.isEmpty
                    ? const Center(child: Text('No customer found'))
                    : GridView.builder(
                      itemCount: controller.customers.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount:
                            MediaQuery.sizeOf(context).width < 700 ? 1 : 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 2.9,
                      ),
                      itemBuilder: (BuildContext context, int index) {
                        final customer = controller.customers[index];
                        return _CustomerCard(
                          customer: customer,
                          selected:
                              controller.selectedCustomer?.id == customer.id,
                          onTap: () async {
                            final selection = controller.selectCustomer(
                              customer,
                            );
                            controller.selectView('Order');
                            await selection;
                          },
                        );
                      },
                    ),
          ),
        ),
      ],
    );
  }

  Future<void> _showCreateCustomerDialog(
    BuildContext context,
    PosHomeController controller,
  ) {
    final nameController = TextEditingController();
    final mobileController = TextEditingController();
    final emailController = TextEditingController();
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Create Customer'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Customer Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: mobileController,
                decoration: const InputDecoration(labelText: 'Mobile No'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                await controller.createCustomer(
                  customerName: nameController.text,
                  mobileNo: mobileController.text,
                  emailId: emailController.text,
                );
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showLookupCustomerDialog(
    BuildContext context,
    PosHomeController controller,
  ) {
    final mobileController = TextEditingController();
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Lookup Customer By Mobile'),
          content: TextField(
            controller: mobileController,
            decoration: const InputDecoration(labelText: 'Mobile No'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                await controller.lookupCustomerByMobile(mobileController.text);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('Search'),
            ),
          ],
        );
      },
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({
    required this.customer,
    required this.selected,
    required this.onTap,
  });

  final PosCustomer customer;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Card(
        color:
            selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.07)
                : Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                backgroundColor:
                    customer.isFrozen
                        ? Theme.of(context).colorScheme.errorContainer
                        : Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.12),
                child: Icon(
                  Icons.store_mall_directory_outlined,
                  color:
                      customer.isFrozen
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      customer.displayName,
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      customer.mobileNo,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (customer.outstandingAmount > 0)
                      Text(
                        'Outstanding ${customer.outstandingAmount.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanSyncView extends StatelessWidget {
  const _PlanSyncView({required this.controller});

  final PosHomeController controller;

  @override
  Widget build(BuildContext context) {
    final dayEntries = controller.plannedEntriesForSelectedDate;
    final plannedCustomerIds =
        dayEntries.map((PosVisitPlanEntry entry) => entry.customerId).toSet();
    final addableCustomers = controller.customers
        .where(
          (PosCustomer customer) => !plannedCustomerIds.contains(customer.id),
        )
        .toList(growable: false);

    return Column(
      children: <Widget>[
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Plan & Sync',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed:
                            () => controller.loadWeekPlan(fromBackend: true),
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: const Text('Refresh Plan'),
                      ),
                      ElevatedButton.icon(
                        onPressed:
                            controller.isBusy
                                ? null
                                : () => controller.syncSelectedDayData(),
                        icon: const Icon(Icons.cloud_sync_outlined),
                        label: const Text('Sync Data'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: controller.currentWeekDates
                    .map(
                      (String isoDate) => ChoiceChip(
                        label: Text(_formatPlanDate(isoDate)),
                        selected: controller.selectedPlanDate == isoDate,
                        onSelected: (_) => controller.selectPlanDate(isoDate),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  _Badge(
                    label: '${dayEntries.length} planned customers',
                    tone: _BadgeTone.neutral,
                  ),
                  _Badge(
                    label:
                        'Offline limit ${controller.bootstrap.offlineSyncCustomerLimit}',
                    tone: _BadgeTone.neutral,
                  ),
                  if (controller.lastDaySyncAt != null)
                    _Badge(
                      label: 'Synced ${controller.lastDaySyncAt!}',
                      tone: _BadgeTone.success,
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Row(
            children: <Widget>[
              Expanded(
                flex: 5,
                child: _SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              'Planned Visits',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed:
                                addableCustomers.isEmpty
                                    ? null
                                    : () => _showAddPlanCustomerDialog(
                                      context,
                                      controller,
                                      addableCustomers,
                                    ),
                            icon: const Icon(Icons.person_add_alt_1),
                            label: const Text('Add Customer'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child:
                            dayEntries.isEmpty
                                ? const Center(
                                  child: Text(
                                    'No customers planned for the selected day.',
                                  ),
                                )
                                : ListView.separated(
                                  itemCount: dayEntries.length,
                                  separatorBuilder:
                                      (_, __) => const SizedBox(height: 12),
                                  itemBuilder: (
                                    BuildContext context,
                                    int index,
                                  ) {
                                    final entry = dayEntries[index];
                                    return _PlanEntryCard(
                                      entry: entry,
                                      isFirst: index == 0,
                                      isLast: index == dayEntries.length - 1,
                                      onMoveUp:
                                          () => controller.reorderPlanEntry(
                                            entry,
                                            -1,
                                          ),
                                      onMoveDown:
                                          () => controller.reorderPlanEntry(
                                            entry,
                                            1,
                                          ),
                                      onMove:
                                          () => _showMovePlanEntryDialog(
                                            context,
                                            controller,
                                            entry,
                                          ),
                                      onDelete:
                                          () =>
                                              controller.deletePlanEntry(entry),
                                    );
                                  },
                                ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 4,
                child: _SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Offline Readiness',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Use Sync Data before going offline. Neuradix downloads the day plan, customer directory, base item details, item images, and customer-specific prices for only the selected day.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 16),
                      const _BulletLine(
                        text:
                            'Planned customers can be edited only while online.',
                      ),
                      const _BulletLine(
                        text:
                            'Offline ordering is blocked for customers without a synced day price pack.',
                      ),
                      const _BulletLine(
                        text:
                            'Item image changes in the backend are picked up by the next Sync Data run.',
                      ),
                      const SizedBox(height: 18),
                      Text('${controller.customers.length} customers cached'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showAddPlanCustomerDialog(
    BuildContext context,
    PosHomeController controller,
    List<PosCustomer> customers,
  ) async {
    PosCustomer? selectedCustomer =
        customers.isNotEmpty ? customers.first : null;
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('Add Planned Customer'),
              content: SizedBox(
                width: 520,
                child: DropdownButtonFormField<PosCustomer>(
                  value: selectedCustomer,
                  items: customers
                      .map(
                        (PosCustomer customer) => DropdownMenuItem<PosCustomer>(
                          value: customer,
                          child: Text(customer.displayName),
                        ),
                      )
                      .toList(growable: false),
                  onChanged:
                      (PosCustomer? value) =>
                          setState(() => selectedCustomer = value),
                  decoration: const InputDecoration(labelText: 'Customer'),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed:
                      selectedCustomer == null
                          ? null
                          : () async {
                            await controller.addPlanCustomer(selectedCustomer!);
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                          },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showMovePlanEntryDialog(
    BuildContext context,
    PosHomeController controller,
    PosVisitPlanEntry entry,
  ) async {
    String selectedDate = entry.visitDate;
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('Move Planned Visit'),
              content: DropdownButtonFormField<String>(
                value: selectedDate,
                items: controller.currentWeekDates
                    .map(
                      (String isoDate) => DropdownMenuItem<String>(
                        value: isoDate,
                        child: Text(_formatPlanDate(isoDate)),
                      ),
                    )
                    .toList(growable: false),
                onChanged:
                    (String? value) =>
                        setState(() => selectedDate = value ?? selectedDate),
                decoration: const InputDecoration(labelText: 'Visit Date'),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed:
                      selectedDate == entry.visitDate
                          ? null
                          : () async {
                            await controller.movePlanEntry(entry, selectedDate);
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                          },
                  child: const Text('Move'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _PlanEntryCard extends StatelessWidget {
  const _PlanEntryCard({
    required this.entry,
    required this.isFirst,
    required this.isLast,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onMove,
    required this.onDelete,
  });

  final PosVisitPlanEntry entry;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onMove;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              backgroundColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.12),
              child: Text('${entry.sequenceNo}'),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    entry.customerName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.customerCode.isEmpty
                        ? entry.customerId
                        : '${entry.customerId} • ${entry.customerCode}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (entry.notes.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        entry.notes,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              onPressed: isFirst ? null : onMoveUp,
              icon: const Icon(Icons.arrow_upward),
            ),
            IconButton(
              onPressed: isLast ? null : onMoveDown,
              icon: const Icon(Icons.arrow_downward),
            ),
            IconButton(
              onPressed: onMove,
              icon: const Icon(Icons.drive_file_move_outline),
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryView extends StatelessWidget {
  const _HistoryView({required this.controller});

  final PosHomeController controller;

  @override
  Widget build(BuildContext context) {
    final orders = controller.history;
    return Column(
      children: <Widget>[
        _SectionCard(
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Order History',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              _Badge(
                label: '${orders.length} orders',
                tone: _BadgeTone.neutral,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _SectionCard(
            child:
                orders.isEmpty
                    ? const Center(child: Text('No history available'))
                    : ListView.builder(
                      itemCount: orders.length,
                      itemBuilder: (context, index) {
                        final order = orders[index];
                        return Card(
                          child: ListTile(
                            title: Text(order.id),
                            subtitle: Text(
                              '${order.customer} • ${order.transactionDate}\n${order.status} • ${order.items.length} items',
                            ),
                            trailing: Text(order.grandTotal.toStringAsFixed(2)),
                            onTap:
                                () => showHistoryOrderDetails(context, order),
                          ),
                        );
                      },
                    ),
          ),
        ),
      ],
    );
  }
}

Future<void> showHistoryOrderDetails(
  BuildContext context,
  PosHistoryOrder order,
) => showDialog<void>(
  context: context,
  builder:
      (context) => AlertDialog(
        title: Text(order.id),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${order.customer} • ${order.transactionDate}'),
                Text(
                  order.isParked
                      ? 'Parked'
                      : order.isLocalOnly
                      ? 'Queued'
                      : order.status,
                ),
                for (final key in [
                  'delivery_date',
                  'mode_of_payment',
                  'total',
                  'total_taxes_and_charges',
                  'notes',
                  'additional_notes',
                ])
                  if ('${order.savedDetails[key] ?? ''}'.isNotEmpty)
                    Text(
                      '${key.replaceAll('_', ' ')}: ${order.savedDetails[key]}',
                    ),
                const Divider(),
                for (final item in order.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.itemName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(item.itemCode),
                        Text(
                          'Quantity ${item.qty} ${item.savedDetails['uom'] ?? ''} • Rate ${item.rate.toStringAsFixed(2)} • Line total ${item.savedDetails['amount'] ?? (item.qty * item.rate).toStringAsFixed(2)}',
                        ),
                        if (item.notes.isNotEmpty)
                          Text('Comments: ${item.notes}'),
                        for (final sub in item.subItems)
                          Text(
                            'Associated item: ${sub.entries.map((e) => '${e.key}: ${e.value}').join(' • ')}',
                          ),
                      ],
                    ),
                  ),
                const Divider(),
                Text(
                  'Grand total ${order.grandTotal.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
);

class _ProfileView extends StatelessWidget {
  const _ProfileView({
    required this.controller,
    required this.onLogout,
    required this.onChangePassword,
  });

  final PosHomeController controller;
  final Future<void> Function() onLogout;
  final Future<void> Function(String newPassword) onChangePassword;

  @override
  Widget build(BuildContext context) {
    final account =
        controller.account ??
        PosAccountSummary(
          hubManager: controller.session.hubManager,
          fullName: controller.session.username,
          email: controller.session.email,
          mobileNo: '',
          imageUrl: '',
          currencySymbol: controller.bootstrap.currencySymbol,
          balance: 0,
          series: '',
          submittedOrdersToday: 0,
          lastOrderDate: '',
          lastTransactionDate: '',
        );

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('My Profile', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              Expanded(
                child: _ProfileStatCard(
                  title: account.fullName,
                  subtitle: account.email,
                  icon: Icons.account_circle_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ProfileStatCard(
                  title:
                      '${account.balance.toStringAsFixed(2)} ${account.currencySymbol}',
                  subtitle: 'Cash balance',
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ProfileStatCard(
                  title:
                      account.lastTransactionDate.isEmpty
                          ? 'No transactions yet'
                          : account.lastTransactionDate,
                  subtitle: 'Last transaction date',
                  icon: Icons.calendar_today_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Finance',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Today you have ${account.submittedOrdersToday} submitted orders. Series ${account.series.isEmpty ? 'SO-' : account.series} is active for this operator.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Security',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Password changes are sent directly to the Neuradix backend for the signed-in operator.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed:
                              () => _showChangePasswordDialog(
                                context,
                                onChangePassword,
                              ),
                          child: const Text('Change Password'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Align(
            alignment: Alignment.bottomRight,
            child: ElevatedButton.icon(
              onPressed: () => onLogout(),
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showChangePasswordDialog(
    BuildContext context,
    Future<void> Function(String newPassword) onChangePassword,
  ) {
    final passwordController = TextEditingController();
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Change Password'),
          content: TextField(
            controller: passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'New Password'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                await onChangePassword(passwordController.text);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}

class _ProfileStatCard extends StatelessWidget {
  const _ProfileStatCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              backgroundColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.12),
              child: Icon(icon, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuantityEditor extends StatelessWidget {
  const _QuantityEditor({
    required this.qty,
    required this.onDecrease,
    required this.onIncrease,
  });

  final int qty;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).dividerTheme.color ?? Colors.black12,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(onPressed: onDecrease, icon: const Icon(Icons.remove)),
          Text('$qty', style: Theme.of(context).textTheme.titleLarge),
          IconButton(onPressed: onIncrease, icon: const Icon(Icons.add)),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final double value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style =
        emphasized
            ? Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20)
            : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: style)),
          Text(value.toStringAsFixed(2), style: style),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    );
  }
}

class _DetailPill extends StatelessWidget {
  const _DetailPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}

enum _BadgeTone { neutral, success, warning, error }

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.tone});

  final String label;
  final _BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor;
    final Color foregroundColor;
    switch (tone) {
      case _BadgeTone.success:
        backgroundColor = const Color(0xFFE9F7EE);
        foregroundColor = const Color(0xFF1F7A39);
      case _BadgeTone.warning:
        backgroundColor = const Color(0xFFFFF1D6);
        foregroundColor = const Color(0xFFA45C00);
      case _BadgeTone.error:
        backgroundColor = Theme.of(context).colorScheme.errorContainer;
        foregroundColor = Theme.of(context).colorScheme.error;
      case _BadgeTone.neutral:
        backgroundColor = Theme.of(
          context,
        ).colorScheme.primary.withValues(alpha: 0.10);
        foregroundColor = Theme.of(context).colorScheme.primary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(color: foregroundColor),
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.message, required this.backgroundColor});

  final String message;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(message, style: Theme.of(context).textTheme.bodyLarge),
    );
  }
}

class _BulletLine extends StatelessWidget {
  const _BulletLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}

String _formatPlanDate(String isoDate) {
  final value = DateTime.parse(isoDate);
  const weekdayNames = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  const monthNames = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${weekdayNames[value.weekday - 1]} ${value.day} ${monthNames[value.month - 1]}';
}
