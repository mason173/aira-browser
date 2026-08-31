use adblock::{
    Engine,
    cosmetic_filter_cache::UrlSpecificResources,
    lists::{FilterSet, ParseOptions, ParsedLine, RuleTypes, parse_filter},
    request::Request,
    resources::Resource,
};
use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64_STANDARD};
use std::{
    fs,
    panic::{AssertUnwindSafe, catch_unwind},
    slice, str,
};

const STATUS_OK: i32 = 0;
const STATUS_INVALID_ARGUMENT: i32 = 1;
const STATUS_IO_ERROR: i32 = 2;
const STATUS_REQUEST_ERROR: i32 = 3;
const STATUS_PANIC: i32 = 4;
const MAX_RULESET_BYTES: u64 = 40 * 1024 * 1024;
const MAX_PATH_BYTES: usize = 4096;
const MAX_URL_BYTES: usize = 64 * 1024;
const MAX_REQUEST_TYPE_BYTES: usize = 32;
const MAX_METHOD_BYTES: usize = 32;
const MAX_REDIRECT_DATA_URL_BYTES: usize = 512 * 1024;
const MAX_COSMETIC_INPUT_JSON_BYTES: usize = 512 * 1024;
const BRAVE_REDIRECT_RESOURCES: &str = include_str!("../resources/brave-resources-v0.13.2.json");

pub struct AiraAdblockEngine {
    engine: Engine,
    network_rule_count: usize,
    cosmetic_rule_count: usize,
}

pub struct AiraAdblockCheckResult {
    should_block: bool,
    csp_directives: String,
    redirect_data_url: String,
    rewritten_url: String,
}

pub struct AiraAdblockCosmeticResult {
    hide_selectors: String,
    procedural_actions: String,
    exceptions: String,
    injected_script: String,
    generichide: bool,
}

fn load_redirect_resources() -> Result<Vec<Resource>, i32> {
    let mut resources: Vec<Resource> =
        serde_json::from_str(BRAVE_REDIRECT_RESOURCES).map_err(|_| STATUS_IO_ERROR)?;
    patch_legacy_window_open_scriptlet(&mut resources)?;
    let aliases = [
        ("noop.txt", "abp-resource:blank-text"),
        ("noop.css", "abp-resource:blank-css"),
        ("noop.html", "abp-resource:blank-html"),
        ("1x1.gif", "abp-resource:1x1-transparent-gif"),
        ("2x2.png", "abp-resource:2x2-transparent-png"),
        ("3x2.png", "abp-resource:3x2-transparent-png"),
        ("32x32.png", "abp-resource:32x32-transparent-png"),
    ];
    for (name, alias) in aliases {
        let resource = resources
            .iter_mut()
            .find(|resource| resource.name == name)
            .ok_or(STATUS_IO_ERROR)?;
        if !resource.aliases.iter().any(|item| item == alias) {
            resource.aliases.push(alias.to_owned());
        }
    }
    Ok(resources)
}

fn patch_legacy_window_open_scriptlet(resources: &mut [Resource]) -> Result<(), i32> {
    let resource = resources
        .iter_mut()
        .find(|resource| resource.name == "prevent-window-open.js")
        .ok_or(STATUS_IO_ERROR)?;
    let source = BASE64_STANDARD
        .decode(&resource.content)
        .map_err(|_| STATUS_IO_ERROR)?;
    let source = String::from_utf8(source).map_err(|_| STATUS_IO_ERROR)?;
    let body_marker = ") {\n    const safe = safeSelf();";
    let compatibility_body = ") {\n    if ( pattern === '0' || pattern === '1' ) {\n        pattern = pattern === '0' ? `!${delay}` : delay;\n        delay = '';\n        decoy = '';\n    }\n    const safe = safeSelf();";
    if !source.contains(body_marker) {
        return Err(STATUS_IO_ERROR);
    }
    resource.content = BASE64_STANDARD.encode(source.replacen(body_marker, compatibility_body, 1));
    Ok(())
}

fn read_utf8<'a>(
    value: *const u8,
    length: usize,
    maximum: usize,
    allow_empty: bool,
) -> Result<&'a str, i32> {
    if value.is_null() || length > maximum || (!allow_empty && length == 0) {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let bytes = unsafe { slice::from_raw_parts(value, length) };
    str::from_utf8(bytes).map_err(|_| STATUS_INVALID_ARGUMENT)
}

#[unsafe(no_mangle)]
/// Builds an engine from the UTF-8 ruleset path and transfers its ownership to the caller.
///
/// # Safety
///
/// `path` must reference `path_length` readable bytes for the duration of this call. `output` must reference writable
/// storage for one engine pointer. On success the caller must release that pointer exactly once with
/// [`aira_adblock_engine_destroy`].
pub unsafe extern "C" fn aira_adblock_engine_create_from_file(
    path: *const u8,
    path_length: usize,
    output: *mut *mut AiraAdblockEngine,
) -> i32 {
    if output.is_null() {
        return STATUS_INVALID_ARGUMENT;
    }
    unsafe { *output = std::ptr::null_mut() };
    let result = catch_unwind(AssertUnwindSafe(
        || -> Result<*mut AiraAdblockEngine, i32> {
            let path = read_utf8(path, path_length, MAX_PATH_BYTES, false)?;
            let metadata = fs::metadata(path).map_err(|_| STATUS_IO_ERROR)?;
            if !metadata.is_file() || metadata.len() == 0 || metadata.len() > MAX_RULESET_BYTES {
                return Err(STATUS_IO_ERROR);
            }
            let rules = fs::read_to_string(path).map_err(|_| STATUS_IO_ERROR)?;
            let parse_options = ParseOptions {
                rule_types: RuleTypes::All,
                ..ParseOptions::default()
            };
            let (network_rule_count, cosmetic_rule_count) =
                rules
                    .lines()
                    .fold((0usize, 0usize), |(network_count, cosmetic_count), line| {
                        match parse_filter(line, false, parse_options) {
                            Ok(ParsedLine::Network(_)) => (network_count + 1, cosmetic_count),
                            Ok(ParsedLine::Cosmetic(_)) => (network_count, cosmetic_count + 1),
                            Err(_) => (network_count, cosmetic_count),
                        }
                    });
            let mut filter_set = FilterSet::new(false);
            filter_set.add_filter_list(rules, parse_options);
            let mut engine = Engine::new_with_filter_set(filter_set);
            engine.use_resources(load_redirect_resources()?);
            Ok(Box::into_raw(Box::new(AiraAdblockEngine {
                engine,
                network_rule_count,
                cosmetic_rule_count,
            })))
        },
    ));
    match result {
        Ok(Ok(engine)) => {
            unsafe { *output = engine };
            STATUS_OK
        }
        Ok(Err(status)) => status,
        Err(_) => STATUS_PANIC,
    }
}

#[unsafe(no_mangle)]
/// Releases an engine returned by [`aira_adblock_engine_create_from_file`].
///
/// # Safety
///
/// `engine` must be null or a live pointer returned by [`aira_adblock_engine_create_from_file`] that has not already
/// been released. The pointer must not be used after this call.
pub unsafe extern "C" fn aira_adblock_engine_destroy(engine: *mut AiraAdblockEngine) {
    if engine.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        drop(Box::from_raw(engine));
    }));
}

#[unsafe(no_mangle)]
/// Returns the number of network rules accepted while building this engine.
///
/// # Safety
///
/// `engine` must remain live for this call.
pub unsafe extern "C" fn aira_adblock_engine_network_rule_count(
    engine: *const AiraAdblockEngine,
) -> usize {
    if engine.is_null() {
        return 0;
    }
    unsafe { &*engine }.network_rule_count
}

#[unsafe(no_mangle)]
/// Returns the number of cosmetic or scriptlet rules accepted while building this engine.
///
/// # Safety
///
/// `engine` must remain live for this call.
pub unsafe extern "C" fn aira_adblock_engine_cosmetic_rule_count(
    engine: *const AiraAdblockEngine,
) -> usize {
    if engine.is_null() {
        return 0;
    }
    unsafe { &*engine }.cosmetic_rule_count
}

#[unsafe(no_mangle)]
/// Returns the total number of rules accepted while building this engine.
///
/// # Safety
///
/// `engine` must remain live for this call.
pub unsafe extern "C" fn aira_adblock_engine_rule_count(engine: *const AiraAdblockEngine) -> usize {
    if engine.is_null() {
        return 0;
    }
    let engine = unsafe { &*engine };
    engine.network_rule_count + engine.cosmetic_rule_count
}

#[unsafe(no_mangle)]
/// Checks one request against a live engine and transfers the result to the caller.
///
/// # Safety
///
/// `engine` must remain live for this call. Each string pointer must reference its declared readable byte length, and
/// `output` must reference writable storage for one result pointer. On success the caller must release that pointer
/// exactly once with [`aira_adblock_check_result_destroy`]. Concurrent calls require an engine built without
/// adblock-rust's `single-thread` feature, as configured by this crate.
pub unsafe extern "C" fn aira_adblock_engine_check(
    engine: *const AiraAdblockEngine,
    url: *const u8,
    url_length: usize,
    source_url: *const u8,
    source_url_length: usize,
    request_type: *const u8,
    request_type_length: usize,
    method: *const u8,
    method_length: usize,
    include_csp: u8,
    output: *mut *mut AiraAdblockCheckResult,
) -> i32 {
    if engine.is_null() || output.is_null() {
        return STATUS_INVALID_ARGUMENT;
    }
    unsafe { *output = std::ptr::null_mut() };
    let result = catch_unwind(AssertUnwindSafe(
        || -> Result<*mut AiraAdblockCheckResult, i32> {
            let url = read_utf8(url, url_length, MAX_URL_BYTES, false)?;
            let source_url = read_utf8(source_url, source_url_length, MAX_URL_BYTES, true)?;
            let request_type = read_utf8(
                request_type,
                request_type_length,
                MAX_REQUEST_TYPE_BYTES,
                false,
            )?;
            let method = read_utf8(method, method_length, MAX_METHOD_BYTES, false)?;
            let request = Request::new(url, source_url, request_type, method)
                .map_err(|_| STATUS_REQUEST_ERROR)?;
            let engine = unsafe { &*engine };
            let blocker_result = engine.engine.check_network_request(&request);
            let should_block = blocker_result.should_block();
            let redirect_data_url = if should_block {
                blocker_result.redirect.unwrap_or_default()
            } else {
                String::new()
            };
            let rewritten_url = blocker_result.rewritten_url.unwrap_or_default();
            if redirect_data_url.len() > MAX_REDIRECT_DATA_URL_BYTES {
                return Err(STATUS_REQUEST_ERROR);
            }
            let csp_directives = if include_csp != 0 {
                engine
                    .engine
                    .get_csp_directives(&request)
                    .unwrap_or_default()
            } else {
                String::new()
            };
            Ok(Box::into_raw(Box::new(AiraAdblockCheckResult {
                should_block,
                csp_directives,
                redirect_data_url,
                rewritten_url,
            })))
        },
    ));
    match result {
        Ok(Ok(result)) => {
            unsafe { *output = result };
            STATUS_OK
        }
        Ok(Err(status)) => status,
        Err(_) => STATUS_PANIC,
    }
}

#[unsafe(no_mangle)]
/// Releases a result returned by [`aira_adblock_engine_check`].
///
/// # Safety
///
/// `result` must be null or a live pointer returned by [`aira_adblock_engine_check`] that has not already been released.
pub unsafe extern "C" fn aira_adblock_check_result_destroy(result: *mut AiraAdblockCheckResult) {
    if result.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        drop(Box::from_raw(result));
    }));
}

#[unsafe(no_mangle)]
/// Returns whether the checked request should be blocked.
///
/// # Safety
///
/// `result` must remain live for this call.
pub unsafe extern "C" fn aira_adblock_check_result_should_block(
    result: *const AiraAdblockCheckResult,
) -> u8 {
    if result.is_null() {
        return 0;
    }
    u8::from(unsafe { &*result }.should_block)
}

unsafe fn result_string(
    result: *const AiraAdblockCheckResult,
    select: impl FnOnce(&AiraAdblockCheckResult) -> &str,
    length: *mut usize,
) -> *const u8 {
    if result.is_null() || length.is_null() {
        return std::ptr::null();
    }
    let value = select(unsafe { &*result });
    unsafe { *length = value.len() };
    value.as_ptr()
}

#[unsafe(no_mangle)]
/// Borrows the result's CSP UTF-8 bytes until the result is released.
///
/// # Safety
///
/// `result` must remain live for this call and `length` must reference writable storage.
pub unsafe extern "C" fn aira_adblock_check_result_csp(
    result: *const AiraAdblockCheckResult,
    length: *mut usize,
) -> *const u8 {
    unsafe { result_string(result, |value| &value.csp_directives, length) }
}

#[unsafe(no_mangle)]
/// Borrows the result's redirect data URL UTF-8 bytes until the result is released.
///
/// # Safety
///
/// `result` must remain live for this call and `length` must reference writable storage.
pub unsafe extern "C" fn aira_adblock_check_result_redirect(
    result: *const AiraAdblockCheckResult,
    length: *mut usize,
) -> *const u8 {
    unsafe { result_string(result, |value| &value.redirect_data_url, length) }
}

#[unsafe(no_mangle)]
/// Borrows the result's rewritten URL UTF-8 bytes until the result is released.
///
/// # Safety
///
/// `result` must remain live for this call and `length` must reference writable storage.
pub unsafe extern "C" fn aira_adblock_check_result_rewritten_url(
    result: *const AiraAdblockCheckResult,
    length: *mut usize,
) -> *const u8 {
    unsafe { result_string(result, |value| &value.rewritten_url, length) }
}

#[unsafe(no_mangle)]
/// Queries Rust-owned cosmetic resources for one page URL.
///
/// # Safety
///
/// `engine` must remain live for this call. Each input pointer must reference its declared readable byte length, and
/// `output` must reference writable storage for one result pointer. On success the caller must release that pointer
/// exactly once with [`aira_adblock_cosmetic_result_destroy`].
pub unsafe extern "C" fn aira_adblock_engine_cosmetic_resources(
    engine: *const AiraAdblockEngine,
    url: *const u8,
    url_length: usize,
    classes_json: *const u8,
    classes_json_length: usize,
    ids_json: *const u8,
    ids_json_length: usize,
    output: *mut *mut AiraAdblockCosmeticResult,
) -> i32 {
    if engine.is_null() || output.is_null() {
        return STATUS_INVALID_ARGUMENT;
    }
    unsafe { *output = std::ptr::null_mut() };
    let result = catch_unwind(AssertUnwindSafe(
        || -> Result<*mut AiraAdblockCosmeticResult, i32> {
            let url = read_utf8(url, url_length, MAX_URL_BYTES, false)?;
            let classes_json = read_utf8(
                classes_json,
                classes_json_length,
                MAX_COSMETIC_INPUT_JSON_BYTES,
                false,
            )?;
            let ids_json = read_utf8(
                ids_json,
                ids_json_length,
                MAX_COSMETIC_INPUT_JSON_BYTES,
                false,
            )?;
            let classes: Vec<String> =
                serde_json::from_str(classes_json).map_err(|_| STATUS_INVALID_ARGUMENT)?;
            let ids: Vec<String> =
                serde_json::from_str(ids_json).map_err(|_| STATUS_INVALID_ARGUMENT)?;
            let engine = unsafe { &*engine };
            let resources: UrlSpecificResources = engine.engine.url_cosmetic_resources(url);
            let mut hide_selectors: Vec<String> =
                resources.hide_selectors.iter().cloned().collect();
            if !resources.generichide {
                hide_selectors.extend(engine.engine.hidden_class_id_selectors(
                    &classes,
                    &ids,
                    &resources.exceptions,
                ));
            }
            hide_selectors.sort_unstable();
            hide_selectors.dedup();
            let mut procedural_actions: Vec<String> =
                resources.procedural_actions.iter().cloned().collect();
            procedural_actions.sort_unstable();
            let mut exceptions: Vec<String> = resources.exceptions.iter().cloned().collect();
            exceptions.sort_unstable();
            Ok(Box::into_raw(Box::new(AiraAdblockCosmeticResult {
                hide_selectors: serde_json::to_string(&hide_selectors)
                    .map_err(|_| STATUS_IO_ERROR)?,
                procedural_actions: serde_json::to_string(&procedural_actions)
                    .map_err(|_| STATUS_IO_ERROR)?,
                exceptions: serde_json::to_string(&exceptions).map_err(|_| STATUS_IO_ERROR)?,
                injected_script: resources.injected_script,
                generichide: resources.generichide,
            })))
        },
    ));
    match result {
        Ok(Ok(value)) => {
            unsafe { *output = value };
            STATUS_OK
        }
        Ok(Err(status)) => status,
        Err(_) => STATUS_PANIC,
    }
}

#[unsafe(no_mangle)]
/// Releases a cosmetic result returned by [`aira_adblock_engine_cosmetic_resources`].
///
/// # Safety
///
/// `result` must be null or a live result pointer that has not already been released.
pub unsafe extern "C" fn aira_adblock_cosmetic_result_destroy(
    result: *mut AiraAdblockCosmeticResult,
) {
    if result.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe { drop(Box::from_raw(result)) }));
}

unsafe fn cosmetic_result_string(
    result: *const AiraAdblockCosmeticResult,
    select: impl FnOnce(&AiraAdblockCosmeticResult) -> &str,
    length: *mut usize,
) -> *const u8 {
    if result.is_null() || length.is_null() {
        return std::ptr::null();
    }
    let value = select(unsafe { &*result });
    unsafe { *length = value.len() };
    value.as_ptr()
}

#[unsafe(no_mangle)]
/// Borrows the result's hide-selector JSON UTF-8 bytes until the result is released.
///
/// # Safety
///
/// `result` must remain live for this call and `length` must reference writable storage.
pub unsafe extern "C" fn aira_adblock_cosmetic_result_hide_selectors(
    result: *const AiraAdblockCosmeticResult,
    length: *mut usize,
) -> *const u8 {
    unsafe { cosmetic_result_string(result, |value| &value.hide_selectors, length) }
}

#[unsafe(no_mangle)]
/// Borrows the result's procedural-action JSON UTF-8 bytes until the result is released.
///
/// # Safety
///
/// `result` must remain live for this call and `length` must reference writable storage.
pub unsafe extern "C" fn aira_adblock_cosmetic_result_procedural_actions(
    result: *const AiraAdblockCosmeticResult,
    length: *mut usize,
) -> *const u8 {
    unsafe { cosmetic_result_string(result, |value| &value.procedural_actions, length) }
}

#[unsafe(no_mangle)]
/// Borrows the result's exception JSON UTF-8 bytes until the result is released.
///
/// # Safety
///
/// `result` must remain live for this call and `length` must reference writable storage.
pub unsafe extern "C" fn aira_adblock_cosmetic_result_exceptions(
    result: *const AiraAdblockCosmeticResult,
    length: *mut usize,
) -> *const u8 {
    unsafe { cosmetic_result_string(result, |value| &value.exceptions, length) }
}

#[unsafe(no_mangle)]
/// Borrows the result's injected-script UTF-8 bytes until the result is released.
///
/// # Safety
///
/// `result` must remain live for this call and `length` must reference writable storage.
pub unsafe extern "C" fn aira_adblock_cosmetic_result_script(
    result: *const AiraAdblockCosmeticResult,
    length: *mut usize,
) -> *const u8 {
    unsafe { cosmetic_result_string(result, |value| &value.injected_script, length) }
}

#[unsafe(no_mangle)]
/// Returns whether generic element hiding is disabled for the queried page.
///
/// # Safety
///
/// `result` must remain live for this call.
pub unsafe extern "C" fn aira_adblock_cosmetic_result_generichide(
    result: *const AiraAdblockCosmeticResult,
) -> u8 {
    if result.is_null() {
        return 0;
    }
    u8::from(unsafe { &*result }.generichide)
}

#[unsafe(no_mangle)]
pub extern "C" fn aira_adblock_engine_version() -> *const std::ffi::c_char {
    c"adblock-rust/0.13.2".as_ptr()
}
