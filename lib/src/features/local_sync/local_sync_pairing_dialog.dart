import 'package:flutter/material.dart';

Future<String?> showLocalSyncPairingApprovalDialog(BuildContext context) async {
  var pairingCode = '';
  final result = await showDialog<String>(
    context: context,
    builder:
        (BuildContext dialogContext) => AlertDialog(
          title: const Text('Approve New Register'),
          content: SizedBox(
            width: 520,
            child: TextField(
              key: const Key('local-sync-pairing-code-input'),
              minLines: 3,
              maxLines: 6,
              onChanged: (String value) => pairingCode = value,
              decoration: const InputDecoration(
                labelText: 'Pairing Code',
                hintText: 'Enter the code shown on the new register',
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              key: const Key('approve-local-sync-pairing'),
              onPressed: () {
                FocusScope.of(dialogContext).unfocus();
                Navigator.of(dialogContext).pop(pairingCode);
              },
              child: const Text('Approve Register'),
            ),
          ],
        ),
  );
  // Let the dialog and its input dependencies finish deactivating before the
  // underlying shell updates its busy state.
  await Future<void>.delayed(kThemeAnimationDuration);
  return result;
}
