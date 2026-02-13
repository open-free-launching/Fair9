@echo off
echo Setting up Flutter Rust Bridge...

rem Check for Codegen
cargo install flutter_rust_bridge_codegen

rem Run Codegen
echo Generating bindings...
flutter_rust_bridge_codegen ^
    --rust-input native/src/api.rs ^
    --dart-output lib/bridge_generated.dart ^
    --dart-decl-output lib/bridge_definitions.dart ^
    --c-output native/bridge_generated.h ^
    --extra-c-output-path native/ios/bridge_generated.h

echo Bindings generated.
echo Now run: flutter run
pause
