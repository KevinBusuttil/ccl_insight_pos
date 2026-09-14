import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DatabaseFactory resolveDatabaseFactory() {
  if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
    sqfliteFfiInit();
    return databaseFactoryFfi;
  }
  return databaseFactory;
}
