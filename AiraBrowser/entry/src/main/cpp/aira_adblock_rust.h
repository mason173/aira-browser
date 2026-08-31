#ifndef AIRA_ADBLOCK_RUST_H
#define AIRA_ADBLOCK_RUST_H

#include <cstddef>
#include <cstdint>

#ifdef __cplusplus
extern "C" {
#endif

struct AiraAdblockEngine;
struct AiraAdblockCheckResult;
struct AiraAdblockCosmeticResult;

// On success, output owns one engine and must release it exactly once.
int32_t aira_adblock_engine_create_from_file(
    const uint8_t* path,
    size_t path_length,
    AiraAdblockEngine** output);

void aira_adblock_engine_destroy(AiraAdblockEngine* engine);
size_t aira_adblock_engine_network_rule_count(const AiraAdblockEngine* engine);
size_t aira_adblock_engine_cosmetic_rule_count(const AiraAdblockEngine* engine);
size_t aira_adblock_engine_rule_count(const AiraAdblockEngine* engine);

// The engine and all input byte ranges must remain valid for the duration of this call. On success, output owns one
// result and must release it exactly once.
int32_t aira_adblock_engine_check(
    const AiraAdblockEngine* engine,
    const uint8_t* url,
    size_t url_length,
    const uint8_t* source_url,
    size_t source_url_length,
    const uint8_t* request_type,
    size_t request_type_length,
    const uint8_t* method,
    size_t method_length,
    uint8_t include_csp,
    AiraAdblockCheckResult** output);

void aira_adblock_check_result_destroy(AiraAdblockCheckResult* result);
uint8_t aira_adblock_check_result_should_block(const AiraAdblockCheckResult* result);
const uint8_t* aira_adblock_check_result_csp(const AiraAdblockCheckResult* result, size_t* length);
const uint8_t* aira_adblock_check_result_redirect(const AiraAdblockCheckResult* result, size_t* length);
const uint8_t* aira_adblock_check_result_rewritten_url(const AiraAdblockCheckResult* result, size_t* length);

int32_t aira_adblock_engine_cosmetic_resources(
    const AiraAdblockEngine* engine,
    const uint8_t* url,
    size_t url_length,
    const uint8_t* classes_json,
    size_t classes_json_length,
    const uint8_t* ids_json,
    size_t ids_json_length,
    AiraAdblockCosmeticResult** output);

void aira_adblock_cosmetic_result_destroy(AiraAdblockCosmeticResult* result);
const uint8_t* aira_adblock_cosmetic_result_hide_selectors(
    const AiraAdblockCosmeticResult* result,
    size_t* length);
const uint8_t* aira_adblock_cosmetic_result_procedural_actions(
    const AiraAdblockCosmeticResult* result,
    size_t* length);
const uint8_t* aira_adblock_cosmetic_result_exceptions(
    const AiraAdblockCosmeticResult* result,
    size_t* length);
const uint8_t* aira_adblock_cosmetic_result_script(
    const AiraAdblockCosmeticResult* result,
    size_t* length);
uint8_t aira_adblock_cosmetic_result_generichide(const AiraAdblockCosmeticResult* result);

const char* aira_adblock_engine_version();

#ifdef __cplusplus
}
#endif

#endif
