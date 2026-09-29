import 'package:flutter/material.dart';

import 'local_sync_models.dart';

class LocalSyncShopDraft {
  const LocalSyncShopDraft({required this.name, required this.code});

  final String name;
  final String code;
}

Future<LocalSyncShopDraft?> showCreateLocalSyncShopDialog(
  BuildContext context,
) {
  var shopName = '';
  var shopCode = '';
  return showDialog<LocalSyncShopDraft>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: const Text('Create Shop'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextFormField(
              key: const Key('create-shop-name'),
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Shop Name'),
              onChanged: (String value) => shopName = value,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('create-shop-code'),
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Shop Code'),
              onChanged: (String value) => shopCode = value,
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('create-shop-submit'),
            onPressed: () {
              final name = shopName.trim();
              final code = shopCode.trim();
              if (name.isEmpty || code.isEmpty) {
                return;
              }
              Navigator.of(
                dialogContext,
              ).pop(LocalSyncShopDraft(name: name, code: code));
            },
            child: const Text('Create Shop'),
          ),
        ],
      );
    },
  );
}

Future<LocalSyncShop?> showSelectLocalSyncShopDialog(
  BuildContext context,
  List<LocalSyncShop> shops,
) {
  final listHeight = (shops.length * 72.0).clamp(96.0, 360.0).toDouble();
  return showDialog<LocalSyncShop>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: const Text('Assign This Register'),
        content: SizedBox(
          width: 480,
          height: listHeight,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: shops.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              final shop = shops[index];
              return ListTile(
                key: Key('enrollment-shop-${shop.shopId}'),
                leading: const Icon(Icons.storefront_outlined),
                title: Text(shop.shopName),
                subtitle: Text(shop.shopCode),
                onTap: () => Navigator.of(dialogContext).pop(shop),
              );
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel Login'),
          ),
        ],
      );
    },
  );
}
