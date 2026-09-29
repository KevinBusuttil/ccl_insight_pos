const String neuradixDefaultCloudBaseUrlFallback =
    'http://neuradix-cloud.localhost:8018';

class BootstrapConfig {
  const BootstrapConfig({
    required this.baseUrl,
    required this.useSsl,
    required this.deploymentMode,
    required this.planType,
    required this.brandName,
    required this.supportEmail,
    required this.defaultCloudBaseUrl,
    required this.themePrimary,
    required this.themeSecondary,
    required this.themeAccent,
    required this.themeTextOnPrimary,
    required this.themeSurface,
    required this.themeActive,
    this.businessId = '',
    this.businessName = '',
    this.deviceId = '',
    this.deviceName = '',
    this.syncMode = 'device_local',
    this.relayUrl = '',
    this.protocolVersion = 1,
    this.metadataOnly = false,
    this.featureLocalMultiShopSync = false,
    this.shopId = '',
    this.shopName = '',
  });

  final String baseUrl;
  final bool useSsl;
  final String deploymentMode;
  final String planType;
  final String brandName;
  final String supportEmail;
  final String defaultCloudBaseUrl;
  final String themePrimary;
  final String themeSecondary;
  final String themeAccent;
  final String themeTextOnPrimary;
  final String themeSurface;
  final String themeActive;
  final String businessId;
  final String businessName;
  final String deviceId;
  final String deviceName;
  final String syncMode;
  final String relayUrl;
  final int protocolVersion;
  final bool metadataOnly;
  final bool featureLocalMultiShopSync;
  final String shopId;
  final String shopName;

  Map<String, String> asMap() {
    return <String, String>{
      'base_url': baseUrl,
      'use_ssl': useSsl ? '1' : '0',
      'deployment_mode': deploymentMode,
      'plan_type': planType,
      'brand_name': brandName,
      'support_email': supportEmail,
      'default_cloud_base_url': defaultCloudBaseUrl,
      'theme_primary': themePrimary,
      'theme_secondary': themeSecondary,
      'theme_accent': themeAccent,
      'theme_text_on_primary': themeTextOnPrimary,
      'theme_surface': themeSurface,
      'theme_active': themeActive,
      'business_id': businessId,
      'business_name': businessName,
      'device_id': deviceId,
      'device_name': deviceName,
      'sync_mode': syncMode,
      'relay_url': relayUrl,
      'protocol_version': '$protocolVersion',
      'metadata_only': metadataOnly ? '1' : '0',
      'feature_local_multi_shop_sync': featureLocalMultiShopSync ? '1' : '0',
      'shop_id': shopId,
      'shop_name': shopName,
    };
  }

  BootstrapConfig copyWith({
    String? baseUrl,
    bool? useSsl,
    String? deploymentMode,
    String? planType,
    String? brandName,
    String? supportEmail,
    String? defaultCloudBaseUrl,
    String? themePrimary,
    String? themeSecondary,
    String? themeAccent,
    String? themeTextOnPrimary,
    String? themeSurface,
    String? themeActive,
    String? businessId,
    String? businessName,
    String? deviceId,
    String? deviceName,
    String? syncMode,
    String? relayUrl,
    int? protocolVersion,
    bool? metadataOnly,
    bool? featureLocalMultiShopSync,
    String? shopId,
    String? shopName,
  }) {
    return BootstrapConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      useSsl: useSsl ?? this.useSsl,
      deploymentMode: deploymentMode ?? this.deploymentMode,
      planType: planType ?? this.planType,
      brandName: brandName ?? this.brandName,
      supportEmail: supportEmail ?? this.supportEmail,
      defaultCloudBaseUrl: defaultCloudBaseUrl ?? this.defaultCloudBaseUrl,
      themePrimary: themePrimary ?? this.themePrimary,
      themeSecondary: themeSecondary ?? this.themeSecondary,
      themeAccent: themeAccent ?? this.themeAccent,
      themeTextOnPrimary: themeTextOnPrimary ?? this.themeTextOnPrimary,
      themeSurface: themeSurface ?? this.themeSurface,
      themeActive: themeActive ?? this.themeActive,
      businessId: businessId ?? this.businessId,
      businessName: businessName ?? this.businessName,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      syncMode: syncMode ?? this.syncMode,
      relayUrl: relayUrl ?? this.relayUrl,
      protocolVersion: protocolVersion ?? this.protocolVersion,
      metadataOnly: metadataOnly ?? this.metadataOnly,
      featureLocalMultiShopSync:
          featureLocalMultiShopSync ?? this.featureLocalMultiShopSync,
      shopId: shopId ?? this.shopId,
      shopName: shopName ?? this.shopName,
    );
  }
}
