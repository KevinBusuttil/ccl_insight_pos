import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuradix_pos/src/features/hosted/hosted_models.dart';
import 'package:neuradix_pos/src/features/pos/neuradix_api_client.dart';
import 'package:neuradix_pos/src/features/pos/pos_models.dart';

void main() {
  test('login surfaces invalid backend credentials message on 401', () async {
    final client = NeuradixApiClient(
      baseUrl: 'http://neuradix-cassar.localhost:8008',
      httpClient: MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<String, Object?>{
            'message': 'Invalid login credentials',
            'exc_type': 'AuthenticationError',
          }),
          401,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    expect(
      () => client.login(username: 'Administrator', password: 'admin'),
      throwsA(
        isA<NeuradixApiException>().having(
          (NeuradixApiException error) => error.message,
          'message',
          'Invalid login credentials',
        ),
      ),
    );
  });

  test('getCustomers unwraps frappe message envelope', () async {
    final client = NeuradixApiClient(
      baseUrl: 'http://neuradix-cassar.localhost:8008',
      httpClient: MockClient((http.Request request) async {
        expect(
          request.url.path,
          '/api/method/neuradix.api.v1.customers.get_customers',
        );
        expect(request.url.queryParameters['hub_manager'], 'sara.camilleri');
        return http.Response(
          jsonEncode(<String, Object?>{
            'message': <String, Object?>{
              'hub_manager': 'sara.camilleri',
              'customers': <Map<String, Object?>>[
                <String, Object?>{
                  'name': 'All You Need Daily Shop',
                  'customer_name': 'All You Need Daily Shop',
                  'mobile_no': '77260300',
                  'custom_customer_id': 'C002545',
                  'custom_customer_credit_limit': 1500,
                  'custom_customer_outstanding': 0,
                  'custom_frozen_customer': 0,
                },
              ],
            },
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final customers = await client.getCustomers(hubManager: 'sara.camilleri');

    expect(customers, hasLength(1));
    expect(customers.single.id, 'All You Need Daily Shop');
    expect(customers.single.customerCode, 'C002545');
    expect(customers.single.mobileNo, '77260300');
  });

  test('login prefers backend hub manager identity over username', () async {
    final client = NeuradixApiClient(
      baseUrl: 'http://neuradix-cassar.localhost:8008',
      httpClient: MockClient((http.Request request) async {
        expect(request.url.path, '/api/method/neuradix.api.v1.bootstrap.login');
        return http.Response(
          jsonEncode(<String, Object?>{
            'message': <String, Object?>{
              'api_key': 'key',
              'api_secret': 'secret',
              'username': 'sara.camilleri',
              'email': 'sara.camilleri@neuradix.local',
              'hub_manager': 'sara.camilleri@neuradix.local',
            },
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final session = await client.login(
      username: 'sara.camilleri@neuradix.local',
      password: 'secret',
    );

    expect(session.username, 'sara.camilleri');
    expect(session.email, 'sara.camilleri@neuradix.local');
    expect(session.hubManager, 'sara.camilleri@neuradix.local');
  });

  test('external backend sessions normalize stored hub manager to email', () {
    final session = PosLoginSession.fromJson(<String, dynamic>{
      'username': 'sara.camilleri',
      'email': 'sara.camilleri@neuradix.local',
      'hub_manager': 'sara.camilleri',
      'deployment_mode': 'external_backend',
    });

    expect(session.hubManager, 'sara.camilleri@neuradix.local');
  });

  test(
    'registerHostedBusiness sends selected plan and parses hosted metadata',
    () async {
      final client = NeuradixApiClient(
        baseUrl: 'http://127.0.0.1:8018',
        httpClient: MockClient((http.Request request) async {
          expect(
            request.url.path,
            '/api/method/neuradix.api.v1.auth.register_business',
          );
          expect(request.bodyFields['plan_type'], 'free_cloud');
          expect(request.bodyFields['sync_mode'], 'local_multi_shop');
          expect(request.bodyFields['shop_name'], 'Valletta');
          expect(request.bodyFields['shop_code'], 'VALLETTA');
          return http.Response(
            jsonEncode(<String, Object?>{
              'message': <String, Object?>{
                'username': 'owner',
                'email': 'owner@example.com',
                'api_key': 'key',
                'api_secret': 'secret',
                'bootstrap': <String, Object?>{
                  'app_name': 'neuradix-pos',
                  'brand_name': 'Neuradix POS',
                  'support_email': 'support@neuradix.local',
                  'deployment_mode': 'neuradix_cloud',
                  'plan_type': 'free_cloud',
                  'sync_mode': 'local_multi_shop',
                  'relay_url': 'wss://relay.neuradix.test',
                  'protocol_version': 1,
                  'metadata_only': 1,
                  'default_cloud_base_url': 'http://127.0.0.1:8018',
                  'price_list': 'Standard Selling',
                  'offline_history_days': 14,
                  'offline_sync_customer_limit': 10,
                  'minimum_order_amount': 50,
                  'currency_symbol': 'EUR',
                  'notes_bypass_minimum': 1,
                  'theme': <String, Object?>{'primary': '#2B6F77'},
                  'features': <String, Object?>{
                    'hosted_self_registration': 1,
                    'backend_history_sync': 1,
                    'staff_accounts': 0,
                    'local_multi_shop_sync': 1,
                  },
                  'plan_caps': <String, Object?>{
                    'plan_type': 'free_cloud',
                    'sync_enabled': 1,
                    'max_items': 500,
                  },
                },
                'business': <String, Object?>{
                  'business': 'NBIZ-00001',
                  'business_name': 'Corner Shop',
                  'slug': 'corner-shop',
                  'owner_user': 'owner@example.com',
                  'membership_role': 'Owner',
                  'plan_type': 'free_cloud',
                  'subscription_status': 'active',
                  'deployment_mode': 'neuradix_cloud',
                  'sync_mode': 'local_multi_shop',
                  'metadata_only': 1,
                  'relay_url': 'wss://relay.neuradix.test',
                  'protocol_version': 1,
                  'plan_caps': <String, Object?>{'max_items': 500},
                  'features': <String, Object?>{
                    'backend_history_sync': 1,
                    'staff_accounts': 0,
                  },
                },
                'subscription': <String, Object?>{
                  'plan_type': 'free_cloud',
                  'subscription_status': 'active',
                },
              },
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );

      final auth = await client.registerHostedBusiness(
        businessName: 'Corner Shop',
        fullName: 'Owner',
        email: 'owner@example.com',
        password: 'secret',
        deviceId: 'device-1',
        deviceName: 'Tablet',
        planType: 'free_cloud',
        syncMode: 'local_multi_shop',
        shopName: 'Valletta',
        shopCode: 'VALLETTA',
      );

      expect(auth.subscriptionPlanType, 'free_cloud');
      expect(auth.business.planCaps['max_items'], 500);
      expect(auth.business.features['staff_accounts'], isFalse);
      expect(auth.bootstrapJson['plan_type'], 'free_cloud');
      expect(auth.business.syncMode, 'local_multi_shop');
      expect(auth.business.metadataOnly, isTrue);
      expect(auth.business.relayUrl, 'wss://relay.neuradix.test');
    },
  );

  test(
    'local sync metadata and first-device registration use metadata-only APIs',
    () async {
      var requestCount = 0;
      final client = NeuradixApiClient(
        baseUrl: 'http://127.0.0.1:8018',
        apiKey: 'key',
        apiSecret: 'secret',
        httpClient: MockClient((http.Request request) async {
          requestCount += 1;
          if (requestCount == 1) {
            expect(
              request.url.path,
              '/api/method/neuradix.api.v1.local_sync.get_metadata',
            );
          } else {
            expect(
              request.url.path,
              '/api/method/neuradix.api.v1.local_sync.register_first_device',
            );
            expect(request.method, 'POST');
            expect(request.bodyFields['device_id'], 'device-1');
            expect(request.bodyFields['signing_public_key'], 'signing-key');
            expect(request.bodyFields.containsKey('customer'), isFalse);
            expect(request.bodyFields.containsKey('sale'), isFalse);
          }
          return http.Response(
            jsonEncode(<String, Object?>{
              'message': <String, Object?>{
                'business_id': 'NBIZ-00001',
                'metadata_only': 1,
                'devices': <Object?>[],
              },
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );

      final metadata = await client.getLocalSyncMetadata();
      final registration = await client.registerFirstLocalSyncDevice(
        deviceId: 'device-1',
        deviceName: 'Main Till',
        signingPublicKey: 'signing-key',
        exchangePublicKey: 'exchange-key',
      );

      expect(metadata['metadata_only'], 1);
      expect(registration['business_id'], 'NBIZ-00001');
      expect(requestCount, 2);
    },
  );

  test(
    'local sync trust-management calls never send business payloads',
    () async {
      final requests = <http.Request>[];
      final client = NeuradixApiClient(
        baseUrl: 'http://127.0.0.1:8018',
        apiKey: 'key',
        apiSecret: 'secret',
        httpClient: MockClient((http.Request request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(<String, Object?>{
              'message': <String, Object?>{'ok': 1},
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );

      await client.createLocalSyncShop(
        shopName: 'ABP Valletta',
        shopCode: 'ABP-VLT',
      );
      await client.assignLocalSyncDeviceShop(
        deviceId: 'device-1',
        shopId: 'SHOP-2',
      );
      await client.startLocalSyncEnrollment(
        deviceId: 'device-2',
        deviceName: 'Valletta Till',
        signingPublicKey: 'signing-key',
        exchangePublicKey: 'exchange-key',
        shopId: 'SHOP-2',
      );
      await client.approveLocalSyncEnrollment(
        enrollmentId: 'ENROLL-1',
        approverDeviceId: 'device-1',
        encryptedKeyEnvelope: 'opaque-envelope',
      );
      await client.completeLocalSyncEnrollment(
        enrollmentId: 'ENROLL-1',
        deviceId: 'device-2',
      );
      await client.setPreferredLocalSyncDevice(deviceId: 'device-1');
      await client.revokeLocalSyncDevice(
        deviceId: 'device-2',
        approvingDeviceId: 'device-1',
        nextKeyEpoch: 2,
        encryptedKeyEnvelopes: <String, String>{'device-1': 'rotated-envelope'},
      );

      expect(requests.map((http.Request request) => request.url.path), <String>[
        '/api/method/neuradix.api.v1.local_sync.create_shop',
        '/api/method/neuradix.api.v1.local_sync.assign_device_shop',
        '/api/method/neuradix.api.v1.local_sync.start_enrollment',
        '/api/method/neuradix.api.v1.local_sync.approve_enrollment',
        '/api/method/neuradix.api.v1.local_sync.complete_enrollment',
        '/api/method/neuradix.api.v1.local_sync.set_preferred_device',
        '/api/method/neuradix.api.v1.local_sync.revoke_device',
      ]);
      for (final request in requests) {
        expect(request.method, 'POST');
        expect(request.bodyFields.containsKey('customer'), isFalse);
        expect(request.bodyFields.containsKey('customers'), isFalse);
        expect(request.bodyFields.containsKey('sale'), isFalse);
        expect(request.bodyFields.containsKey('sales'), isFalse);
        expect(request.bodyFields.containsKey('inventory'), isFalse);
      }
      expect(
        jsonDecode(
          requests.last.bodyFields['encrypted_key_envelopes']!,
        )['device-1'],
        'rotated-envelope',
      );
    },
  );

  test('registerHostedBusiness surfaces frappe validation details', () async {
    final client = NeuradixApiClient(
      baseUrl: 'http://127.0.0.1:8018',
      httpClient: MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<String, Object?>{
            'exc_type': 'ValidationError',
            '_server_messages': jsonEncode(<String>[
              jsonEncode(<String, Object?>{
                'message': '<div>This is a very common password.</div>',
                'title': 'Password requirements not met',
                'indicator': 'red',
                'raise_exception': 1,
              }),
            ]),
          }),
          417,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    expect(
      () => client.registerHostedBusiness(
        businessName: 'Corner Shop',
        fullName: 'Owner',
        email: 'owner@example.com',
        password: 'password123',
        deviceId: 'device-1',
        deviceName: 'Tablet',
        planType: 'free_cloud',
      ),
      throwsA(
        isA<NeuradixApiException>().having(
          (NeuradixApiException error) => error.message,
          'message',
          'This is a very common password.',
        ),
      ),
    );
  });

  test(
    'tryRegisterHostedBusiness returns inline error without throwing',
    () async {
      final client = NeuradixApiClient(
        baseUrl: 'http://127.0.0.1:8018',
        httpClient: MockClient((http.Request request) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'exc_type': 'ValidationError',
              '_server_messages': jsonEncode(<String>[
                jsonEncode(<String, Object?>{
                  'message': '<div>This is a very common password.</div>',
                  'title': 'Password requirements not met',
                  'indicator': 'red',
                  'raise_exception': 1,
                }),
              ]),
            }),
            417,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );

      final attempt = await client.tryRegisterHostedBusiness(
        businessName: 'Corner Shop',
        fullName: 'Owner',
        email: 'owner@example.com',
        password: 'password123',
        deviceId: 'device-1',
        deviceName: 'Tablet',
        planType: 'free_cloud',
      );

      expect(attempt.auth, isNull);
      expect(attempt.error, isA<NeuradixApiException>());
      expect(
        (attempt.error! as NeuradixApiException).message,
        'This is a very common password.',
      );
    },
  );

  test(
    'tryLoginHosted returns backend auth failure without throwing',
    () async {
      final client = NeuradixApiClient(
        baseUrl: 'http://127.0.0.1:8018',
        httpClient: MockClient((http.Request request) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'message': 'Invalid login credentials',
              'exc_type': 'AuthenticationError',
            }),
            401,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );

      final attempt = await client.tryLoginHosted(
        email: 'owner@example.com',
        password: 'wrong',
        deviceId: 'device-1',
        deviceName: 'Tablet',
      );

      expect(attempt.auth, isNull);
      expect(attempt.error, isA<NeuradixApiException>());
      expect(
        (attempt.error! as NeuradixApiException).message,
        'Invalid login credentials',
      );
    },
  );

  test('submitSalesOrder unwraps frappe message envelope', () async {
    final client = NeuradixApiClient(
      baseUrl: 'http://neuradix-cassar.localhost:8008',
      httpClient: MockClient((http.Request request) async {
        expect(
          request.url.path,
          '/api/method/neuradix.api.v1.orders.submit_sales_order',
        );
        return http.Response(
          jsonEncode(<String, Object?>{
            'message': <String, Object?>{
              'status': 'submitted',
              'sales_order_name': 'SO-0001',
            },
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
      apiKey: 'key',
      apiSecret: 'secret',
    );

    final salesOrderName = await client.submitSalesOrder(<String, Object?>{
      'client_order_id': 'NEURADIX-1',
    });

    expect(salesOrderName, 'SO-0001');
  });

  test('getDaySyncPack parses plan rows and price overlays', () async {
    final client = NeuradixApiClient(
      baseUrl: 'http://neuradix-cassar.localhost:8008',
      httpClient: MockClient((http.Request request) async {
        expect(
          request.url.path,
          '/api/method/neuradix.api.v1.offline_sync.get_day_sync_pack',
        );
        return http.Response(
          jsonEncode(<String, Object?>{
            'message': <String, Object?>{
              'sales_rep': 'sara.camilleri',
              'sync_date': '2026-06-10',
              'week_start': '2026-06-08',
              'sync_customer_limit': 10,
              'plan_entries': <Map<String, Object?>>[
                <String, Object?>{
                  'name': 'PLAN-001',
                  'sales_rep': 'sara.camilleri',
                  'customer': 'All You Need Daily Shop',
                  'customer_name': 'All You Need Daily Shop',
                  'customer_code': 'C002545',
                  'visit_date': '2026-06-10',
                  'sequence_no': 1,
                },
              ],
              'customer_directory': <Map<String, Object?>>[
                <String, Object?>{
                  'name': 'All You Need Daily Shop',
                  'customer_name': 'All You Need Daily Shop',
                  'custom_customer_id': 'C002545',
                },
              ],
              'catalog_groups': <Map<String, Object?>>[
                <String, Object?>{
                  'item_group': 'Coffee',
                  'items': <Map<String, Object?>>[
                    <String, Object?>{
                      'item_code': 'COFFEE-001',
                      'item_name': 'Classic Blend Beans',
                      'image': '/files/coffee.png',
                      'image_version': '2026-06-10 10:00:00',
                      'product_price': 11.5,
                      'stock_qty': 18,
                    },
                  ],
                },
              ],
              'customer_price_rows': <Map<String, Object?>>[
                <String, Object?>{
                  'customer': 'All You Need Daily Shop',
                  'custom_customer_id': 'C002545',
                  'item_code': 'COFFEE-001',
                  'price': 9.75,
                },
              ],
              'customer_policy_rows': <Map<String, Object?>>[
                <String, Object?>{
                  'customer': 'All You Need Daily Shop',
                  'custom_customer_id': 'C002545',
                  'minimum_order_amount': 50,
                  'minimum_order_required': 1,
                  'notes_bypass_minimum': 1,
                },
              ],
              'image_manifest': <Map<String, Object?>>[
                <String, Object?>{
                  'item_code': 'COFFEE-001',
                  'image_url': '/files/coffee.png',
                  'image_version': '2026-06-10 10:00:00',
                },
              ],
              'sync_cursors': <String, Object?>{
                'customer_modified_through': '2026-06-10 10:10:00',
                'catalog_modified_through': '2026-06-10 10:00:00',
              },
            },
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
      apiKey: 'key',
      apiSecret: 'secret',
    );

    final pack = await client.getDaySyncPack(syncDate: '2026-06-10');

    expect(pack.planEntries, hasLength(1));
    expect(pack.customerPriceRows.single.price, 9.75);
    expect(
      pack.catalogGroups.single.items.single.imageVersion,
      '2026-06-10 10:00:00',
    );
    expect(pack.syncCursors['catalog_modified_through'], '2026-06-10 10:00:00');
  });

  test(
    'upsertHostedInventoryItem uploads image and barcode before saving',
    () async {
      final requests = <http.Request>[];
      final client = NeuradixApiClient(
        baseUrl: 'http://127.0.0.1:8018',
        httpClient: MockClient((http.Request request) async {
          requests.add(request);
          if (request.url.path ==
              '/api/method/neuradix.api.v1.inventory.upload_item_image') {
            expect(request.method, 'POST');
            expect(request.bodyFields['file_name'], 'coffee.png');
            expect(request.bodyFields['mime_type'], 'image/png');
            return http.Response(
              jsonEncode(<String, Object?>{
                'message': <String, Object?>{'file_url': '/files/coffee.png'},
              }),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }
          if (request.url.path ==
              '/api/method/neuradix.api.v1.inventory.upsert_item') {
            final payload = jsonDecode(request.bodyFields['payload']!) as Map;
            expect(payload['barcode'], '5353535353');
            expect(payload['image_url'], '/files/coffee.png');
            return http.Response(
              jsonEncode(<String, Object?>{
                'message': <String, Object?>{
                  'item': <String, Object?>{
                    'name': 'NPROD-0001',
                    'product_code': 'COFFEE-001',
                    'barcode': '5353535353',
                    'product_name': 'Classic Blend Beans',
                    'image': '/files/coffee.png',
                    'price': 11.5,
                    'stock_qty': 18,
                    'is_active': 1,
                  },
                },
              }),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }
          throw StateError('Unexpected request ${request.url}');
        }),
        apiKey: 'key',
        apiSecret: 'secret',
      );

      final item = await client.upsertHostedInventoryItem(
        const HostedInventoryItem(
          itemId: 'NPROD-0001',
          sku: 'COFFEE-001',
          barcode: '5353535353',
          displayName: 'Classic Blend Beans',
          imageUrl: '',
          price: 11.5,
          stockQty: 18,
          isActive: true,
        ),
        imageUploadBase64: base64Encode(<int>[1, 2, 3]),
        imageUploadFileName: 'coffee.png',
        imageUploadMimeType: 'image/png',
      );

      expect(requests, hasLength(2));
      expect(item.barcode, '5353535353');
      expect(item.imageUrl, '/files/coffee.png');
    },
  );
}
