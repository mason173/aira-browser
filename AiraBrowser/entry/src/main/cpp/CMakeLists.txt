cmake_minimum_required(VERSION 3.6.0)
project(aira_adblock_native)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Browser downloads use a private native transport. Keep the third-party
# targets separate from the existing ad-block bridge and disable unused curl
# protocols/programs so the HAP only carries the browser-facing core.
set(MBEDTLS_AS_SUBPROJECT ON CACHE BOOL "" FORCE)
set(ENABLE_PROGRAMS OFF CACHE BOOL "" FORCE)
set(ENABLE_TESTING OFF CACHE BOOL "" FORCE)
set(DISABLE_PACKAGE_CONFIG_AND_INSTALL ON CACHE BOOL "" FORCE)
set(GEN_FILES OFF CACHE BOOL "" FORCE)
set(USE_STATIC_MBEDTLS_LIBRARY ON CACHE BOOL "" FORCE)
set(USE_SHARED_MBEDTLS_LIBRARY OFF CACHE BOOL "" FORCE)
add_subdirectory(third_party/mbedtls mbedtls EXCLUDE_FROM_ALL)

# DevEco's OHOS Clang injects --gcc-toolchain even though the OHOS driver does
# not consume it. Mbed TLS treats that benign diagnostic as an error, so keep
# the warning exception local to the vendored crypto targets.
foreach(AIRA_MBEDTLS_TARGET mbedcrypto mbedx509 mbedtls everest p256m)
  if(TARGET ${AIRA_MBEDTLS_TARGET})
    target_compile_options(${AIRA_MBEDTLS_TARGET} PRIVATE -Wno-error=unused-command-line-argument)
  endif()
endforeach()

set(MBEDTLS_INCLUDE_DIRS "${CMAKE_CURRENT_SOURCE_DIR}/third_party/mbedtls/include" CACHE PATH "" FORCE)
set(MBEDTLS_LIBRARY "MbedTLS::mbedtls" CACHE STRING "" FORCE)
set(MBEDX509_LIBRARY "MbedTLS::mbedx509" CACHE STRING "" FORCE)
set(MBEDCRYPTO_LIBRARY "MbedTLS::mbedcrypto" CACHE STRING "" FORCE)
set(MBEDTLS_LIBRARIES "MbedTLS::mbedtls;MbedTLS::mbedx509;MbedTLS::mbedcrypto" CACHE STRING "" FORCE)

set(BUILD_CURL_EXE OFF CACHE BOOL "" FORCE)
set(BUILD_LIBCURL_DOCS OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(BUILD_STATIC_LIBS ON CACHE BOOL "" FORCE)
set(BUILD_STATIC_CURL ON CACHE BOOL "" FORCE)
set(CURL_DISABLE_INSTALL ON CACHE BOOL "" FORCE)
set(CURL_ENABLE_EXPORT_TARGET OFF CACHE BOOL "" FORCE)
set(CURL_DISABLE_TESTS ON CACHE BOOL "" FORCE)
set(ENABLE_CURL_MANUAL OFF CACHE BOOL "" FORCE)
set(HTTP_ONLY ON CACHE BOOL "" FORCE)
set(CURL_ENABLE_SSL ON CACHE BOOL "" FORCE)
set(CURL_USE_MBEDTLS ON CACHE BOOL "" FORCE)
set(CURL_USE_OPENSSL OFF CACHE BOOL "" FORCE)
set(CURL_USE_LIBPSL OFF CACHE BOOL "" FORCE)
set(CURL_USE_LIBSSH2 OFF CACHE BOOL "" FORCE)
set(CURL_USE_LIBSSH OFF CACHE BOOL "" FORCE)
set(CURL_ZLIB OFF CACHE BOOL "" FORCE)
set(CURL_BROTLI OFF CACHE BOOL "" FORCE)
set(CURL_ZSTD OFF CACHE BOOL "" FORCE)
set(ENABLE_THREADED_RESOLVER OFF CACHE BOOL "" FORCE)
add_subdirectory(third_party/curl curl EXCLUDE_FROM_ALL)
if(TARGET libcurl_static)
  target_compile_options(libcurl_static PRIVATE -Wno-error=unused-command-line-argument)
endif()

if(OHOS_ARCH STREQUAL "arm64-v8a")
  set(AIRA_RUST_TARGET "aarch64-unknown-linux-ohos")
elseif(OHOS_ARCH STREQUAL "armeabi-v7a")
  set(AIRA_RUST_TARGET "armv7-unknown-linux-ohos")
elseif(OHOS_ARCH STREQUAL "x86_64")
  set(AIRA_RUST_TARGET "x86_64-unknown-linux-ohos")
else()
  message(FATAL_ERROR "Unsupported Rust target for OHOS_ARCH=${OHOS_ARCH}")
endif()

if(DEFINED ENV{AIRA_RUSTUP_EXECUTABLE})
  set(AIRA_RUSTUP_EXECUTABLE "$ENV{AIRA_RUSTUP_EXECUTABLE}")
else()
  find_program(AIRA_RUSTUP_EXECUTABLE rustup
    PATHS "$ENV{HOME}/.cargo/bin" /opt/homebrew/opt/rustup/bin /usr/local/opt/rustup/bin
    REQUIRED)
endif()
get_filename_component(AIRA_RUSTUP_BIN_DIR "${AIRA_RUSTUP_EXECUTABLE}" DIRECTORY)
execute_process(
  COMMAND "${AIRA_RUSTUP_EXECUTABLE}" which --toolchain 1.97.1 rustc
  RESULT_VARIABLE AIRA_RUSTC_LOOKUP_RESULT
  OUTPUT_VARIABLE AIRA_RUSTC_EXECUTABLE
  ERROR_VARIABLE AIRA_RUSTC_LOOKUP_ERROR
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
if(NOT AIRA_RUSTC_LOOKUP_RESULT EQUAL 0 OR NOT EXISTS "${AIRA_RUSTC_EXECUTABLE}")
  message(FATAL_ERROR "Unable to resolve rustc for Rust toolchain 1.97.1: ${AIRA_RUSTC_LOOKUP_ERROR}")
endif()

set(AIRA_RUST_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/rust/aira_adblock_core")
set(AIRA_RUST_TARGET_DIR "${CMAKE_CURRENT_BINARY_DIR}/rust-target")
set(AIRA_RUST_LIBRARY
  "${AIRA_RUST_TARGET_DIR}/${AIRA_RUST_TARGET}/release/libaira_adblock_core.a")
string(TOUPPER "${AIRA_RUST_TARGET}" AIRA_RUST_TARGET_ENV)
string(REPLACE "-" "_" AIRA_RUST_TARGET_ENV "${AIRA_RUST_TARGET_ENV}")

add_custom_command(
  OUTPUT "${AIRA_RUST_LIBRARY}"
  COMMAND "${AIRA_RUSTUP_EXECUTABLE}" target add
    --toolchain 1.97.1
    "${AIRA_RUST_TARGET}"
  COMMAND ${CMAKE_COMMAND} -E env
    "PATH=${AIRA_RUSTUP_BIN_DIR}:$ENV{PATH}"
    "RUSTUP_TOOLCHAIN=1.97.1"
    "RUSTC=${AIRA_RUSTC_EXECUTABLE}"
    "CARGO_TARGET_DIR=${AIRA_RUST_TARGET_DIR}"
    "CARGO_TARGET_${AIRA_RUST_TARGET_ENV}_LINKER=${CMAKE_C_COMPILER}"
    "CARGO_TARGET_${AIRA_RUST_TARGET_ENV}_AR=${CMAKE_AR}"
    "RUSTFLAGS=-C link-arg=--sysroot=${OHOS_SDK_NATIVE}/sysroot"
    "${AIRA_RUSTUP_EXECUTABLE}" run 1.97.1 cargo build
      --locked
      --release
      --target "${AIRA_RUST_TARGET}"
      --manifest-path "${AIRA_RUST_ROOT}/Cargo.toml"
  DEPENDS
    "${AIRA_RUST_ROOT}/Cargo.toml"
    "${AIRA_RUST_ROOT}/Cargo.lock"
    "${AIRA_RUST_ROOT}/NOTICE.md"
    "${AIRA_RUST_ROOT}/about.toml"
    "${AIRA_RUST_ROOT}/rust-toolchain.toml"
    "${AIRA_RUST_ROOT}/src/lib.rs"
    "${AIRA_RUST_ROOT}/resources/brave-resources-v0.13.2.json"
    "${AIRA_RUST_ROOT}/resources/adblock-rust-MPL-2.0.txt"
    "${AIRA_RUST_ROOT}/resources/SOURCE.md"
  WORKING_DIRECTORY "${AIRA_RUST_ROOT}"
  COMMENT "Building the Aira ad-block Rust authority core for ${AIRA_RUST_TARGET}"
  VERBATIM
)

add_custom_target(aira_adblock_rust_build DEPENDS "${AIRA_RUST_LIBRARY}")
add_library(aira_adblock_rust STATIC IMPORTED GLOBAL)
set_target_properties(aira_adblock_rust PROPERTIES IMPORTED_LOCATION "${AIRA_RUST_LIBRARY}")
add_dependencies(aira_adblock_rust aira_adblock_rust_build)

add_library(aira_adblock SHARED napi_init.cpp)
target_include_directories(aira_adblock PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(aira_adblock PRIVATE aira_adblock_rust libace_napi.z.so)

add_library(aira_download SHARED download_napi.cpp download_core.cpp)
target_include_directories(aira_download PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/third_party/curl/include"
  "${CMAKE_CURRENT_BINARY_DIR}/curl/include"
)
target_compile_definitions(aira_download PRIVATE CURL_STATICLIB)
target_link_libraries(aira_download PRIVATE
  libcurl_static
  MbedTLS::mbedtls
  MbedTLS::mbedx509
  MbedTLS::mbedcrypto
  libace_napi.z.so
)
