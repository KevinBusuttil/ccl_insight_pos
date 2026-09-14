import 'package:flutter_test/flutter_test.dart';
import 'package:neuradix_pos/src/features/pos/pos_models.dart';

void main() {
  test(
    'merges platform and client bootstrap payloads with non-empty settings',
    () {
      final bundle = PosBootstrapBundle.fromResponses(
        <String, dynamic>{
          'app_name': 'neuradix-pos',
          'plan_type': 'free_cloud',
          'plan_caps': <String, dynamic>{
            'plan_type': 'free_cloud',
            'sync_enabled': 1,
            'max_items': 500,
          },
          'price_list': 'Standard Selling',
          'offline_history_days': 14,
          'minimum_order_amount': 50,
          'currency_symbol': 'EUR',
          'notes_bypass_minimum': 1,
          'theme': <String, dynamic>{
            'primary': '#DC1E44',
            'secondary': '#62B146',
            'accent': '#707070',
            'text_on_primary': '#FFFFFF',
            'surface': '#FEF9FA',
            'active': '#4A4A4A',
          },
          'features': <String, dynamic>{
            'offline_sync': 1,
            'issue_statements': true,
          },
        },
        <String, dynamic>{
          'brand_name': 'CassarCamilleri POS',
          'support_email': 'support@neuradix.local',
          'minimum_order_amount': 65,
          'notes_bypass_minimum': true,
        },
      );

      expect(bundle.appName, 'neuradix-pos');
      expect(bundle.brandName, 'CassarCamilleri POS');
      expect(bundle.supportEmail, 'support@neuradix.local');
      expect(bundle.planType, 'free_cloud');
      expect(bundle.priceList, 'Standard Selling');
      expect(bundle.offlineHistoryDays, 14);
      expect(bundle.minimumOrderAmount, 65);
      expect(bundle.currencySymbol, 'EUR');
      expect(bundle.notesBypassMinimum, isTrue);
      expect(bundle.theme.primary, '#DC1E44');
      expect(bundle.theme.surface, '#FEF9FA');
      expect(bundle.theme.active, '#FEF9FA');
      expect(bundle.theme.parkOrderButton, '#4A4A4A');
      expect(bundle.theme.shadowBorder, '#C7C5C5');
      expect(bundle.features['offline_sync'], isTrue);
      expect(bundle.features['issue_statements'], isTrue);
      expect(bundle.planCaps['plan_type'], 'free_cloud');
      expect(bundle.planCaps['max_items'], 500);
    },
  );
}
