@echo off
setlocal

echo Building Rust library for Windows...

:: Get project root
set SCRIPT_DIR=%~dp0
set PROJECT_ROOT=%SCRIPT_DIR%..
set NATIVE_DIR=%PROJECT_ROOT%\native

:: Determine build mode + Sentry telemetry flag (release defaults on,
:: debug defaults off; override with RUST_TELEMETRY=1 / =0).
if "%1"=="release" (
    set PROFILE=release
    set PROFILE_FLAG=--release
    if "%RUST_TELEMETRY%"=="" set RUST_TELEMETRY=1
    if "%RUST_TELEMETRY%"=="0" (
        set FEATURE_FLAGS=
        echo WARNING: Rust telemetry disabled by RUST_TELEMETRY=0
    ) else (
        set FEATURE_FLAGS=--features telemetry
    )
) else (
    set PROFILE=debug
    set PROFILE_FLAG=
    if "%RUST_TELEMETRY%"=="1" (
        set FEATURE_FLAGS=--features telemetry
    ) else (
        set FEATURE_FLAGS=
    )
)

echo Configuration: %PROFILE% %FEATURE_FLAGS%

:: Navigate to Rust directory
cd /d "%NATIVE_DIR%"

:: Build for Windows x86_64
echo Building for: x86_64-pc-windows-msvc
cargo build %PROFILE_FLAG% --target x86_64-pc-windows-msvc %FEATURE_FLAGS%
if %ERRORLEVEL% neq 0 (
    echo ERROR: Rust build failed!
    exit /b 1
)

:: Copy DLL to windows directory
set RUST_LIB=%NATIVE_DIR%\target\x86_64-pc-windows-msvc\%PROFILE%\native.dll
set DEST=%SCRIPT_DIR%native.dll

if exist "%RUST_LIB%" (
    copy /Y "%RUST_LIB%" "%DEST%"
    echo SUCCESS: native.dll copied to %DEST%
) else (
    echo ERROR: native.dll not found at %RUST_LIB%
    exit /b 1
)

echo Rust library built successfully
