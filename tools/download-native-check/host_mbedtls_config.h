// Host tests use the vendored AES implementation with the same CBC primitive
// as production, without building unrelated TLS, entropy or platform features.
#define MBEDTLS_AES_C
#define MBEDTLS_CIPHER_MODE_CBC
