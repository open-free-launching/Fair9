import 'dart:ffi';
import 'dart:io';
import 'bridge_generated.dart';

const base = 'native';
final path = Platform.isWindows ? '$base.dll' : 'lib$base.so';
late final NativeImpl api;

void initApi() {
  // On Windows, we need to ensure the DLL is found. 
  // For development with 'flutter run', it's usually next to the executable.
  final dylib = DynamicLibrary.open(path);
  api = NativeImpl(dylib);
}
