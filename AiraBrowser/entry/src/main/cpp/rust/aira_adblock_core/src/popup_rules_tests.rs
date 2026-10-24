use super::*;
use adblock::{request::Request, Engine};

fn engines(rules: &str) -> (Engine, Engine) {
    let sets = build_rule_sets(rules, ParseOptions::default());
    (
        Engine::new_with_filter_set(sets.ordinary),
        Engine::new_with_filter_set(sets.popup),
    )
}

fn blocks(engine: &Engine, url: &str, source: &str, request_type: &str) -> bool {
    engine
        .check_network_request(&Request::new(url, source, request_type, "GET").unwrap())
        .should_block()
}

const AD: &str = "https://ads.example/banner";
const PAGE: &str = "https://publisher.example/article";

#[test]
fn popup_only_rules_never_block_ordinary_navigation_or_subresources() {
    let (ordinary, popup) = engines("||ads.example^$popup");
    assert!(blocks(&popup, AD, PAGE, "document"));
    for request_type in ["document", "subdocument", "script", "image", "other"] {
        assert!(!blocks(&ordinary, AD, PAGE, request_type), "{request_type}");
    }
}

#[test]
fn popup_exceptions_domain_exclusions_and_party_restrictions_use_opener() {
    let (_, popup) = engines("||ads.example^$popup,third-party,domain=publisher.example|~private.publisher.example\n@@||ads.example/allowed$popup,domain=publisher.example");
    assert!(blocks(&popup, AD, PAGE, "document"));
    assert!(blocks(
        &popup,
        AD,
        "https://sub.publisher.example",
        "document"
    ));
    assert!(!blocks(
        &popup,
        AD,
        "https://private.publisher.example",
        "document"
    ));
    assert!(!blocks(&popup, AD, "https://unrelated.example", "document"));
    assert!(!blocks(
        &popup,
        "https://ads.example/allowed",
        PAGE,
        "document"
    ));
    let (_, first_party) = engines("||ads.example^$popup,~third-party");
    assert!(blocks(
        &first_party,
        AD,
        "https://www.ads.example/page",
        "document"
    ));
    assert!(!blocks(&first_party, AD, PAGE, "document"));
}

#[test]
fn ordinary_rules_and_document_rules_do_not_become_popup_rules() {
    let (ordinary, popup) = engines("||ads.example^\n||document.example^$document");
    assert!(blocks(&ordinary, AD, PAGE, "script"));
    assert!(!blocks(&popup, AD, PAGE, "document"));
    assert!(!blocks(
        &popup,
        "https://document.example",
        PAGE,
        "document"
    ));
}

#[test]
fn mixed_types_retain_both_network_and_popup_behavior() {
    let (ordinary, popup) = engines("||ads.example^$popup,script");
    assert!(blocks(&popup, AD, PAGE, "document"));
    assert!(blocks(&ordinary, AD, PAGE, "script"));
    assert!(!blocks(&ordinary, AD, PAGE, "image"));
    assert!(!blocks(&ordinary, AD, PAGE, "document"));
}

#[test]
fn negative_network_types_remain_scoped_to_network_requests() {
    let (ordinary, popup) = engines("||ads.example^$popup,~script");
    assert!(blocks(&popup, AD, PAGE, "document"));
    assert!(blocks(&ordinary, AD, PAGE, "image"));
    assert!(!blocks(&ordinary, AD, PAGE, "script"));
    assert!(!blocks(&ordinary, AD, PAGE, "document"));
}

#[test]
fn negated_popup_keeps_ordinary_types_without_enabling_popups() {
    let (ordinary, popup) = engines("||ads.example^$~popup,script\n||excluded.example^$~popup");
    assert!(blocks(&ordinary, AD, PAGE, "script"));
    assert!(!blocks(&ordinary, AD, PAGE, "image"));
    assert!(!blocks(&popup, AD, PAGE, "document"));
    assert!(blocks(
        &ordinary,
        "https://excluded.example/a",
        PAGE,
        "image"
    ));
    assert!(!blocks(
        &ordinary,
        "https://excluded.example/a",
        PAGE,
        "document"
    ));
    assert!(!blocks(
        &popup,
        "https://excluded.example/a",
        PAGE,
        "document"
    ));
}

#[test]
fn negated_popup_preserves_default_removeparam_and_csp_request_types() {
    for modifier in ["removeparam=utm", "csp=script-src 'none'"] {
        let (baseline, _) = engines(&format!("||ads.example^${modifier}"));
        let (ordinary, popup) = engines(&format!("||ads.example^$~popup,{modifier}"));
        for request_type in [
            "document",
            "subdocument",
            "script",
            "image",
            "xmlhttprequest",
        ] {
            let request =
                Request::new("https://ads.example/foo?utm=one", PAGE, request_type, "GET").unwrap();
            assert_eq!(
                ordinary.check_network_request(&request).rewritten_url,
                baseline.check_network_request(&request).rewritten_url,
                "{modifier} {request_type}"
            );
            assert_eq!(
                ordinary.get_csp_directives(&request),
                baseline.get_csp_directives(&request),
                "{modifier} {request_type}"
            );
        }
        assert!(!blocks(&popup, AD, PAGE, "document"));
    }
}

#[test]
fn all_includes_popup_but_negative_popup_excludes_it() {
    let (ordinary, popup) = engines("||ads.example^$all\n||excluded.example^$all,~popup");
    assert!(blocks(&popup, AD, PAGE, "document"));
    assert!(blocks(&ordinary, AD, PAGE, "document"));
    assert!(blocks(&ordinary, AD, PAGE, "script"));
    assert!(blocks(
        &ordinary,
        "https://excluded.example",
        PAGE,
        "document"
    ));
    assert!(!blocks(
        &popup,
        "https://excluded.example",
        PAGE,
        "document"
    ));
}

#[test]
fn negated_popup_wins_over_positive_popup_without_broadening_normal_types() {
    let (ordinary, popup) = engines("||ads.example^$popup,~popup");
    assert!(!blocks(&popup, AD, PAGE, "document"));
    assert!(!blocks(&ordinary, AD, PAGE, "script"));
}

#[test]
fn unsupported_modifiers_are_rejected_instead_of_stripped() {
    let (ordinary, popup) =
        engines("||ads.example^$popup,script,unknown-option\n||ads.example^$popup,popunder");
    assert!(!blocks(&popup, AD, PAGE, "document"));
    assert!(!blocks(&ordinary, AD, PAGE, "script"));
}

#[test]
fn badfilter_disables_the_whole_matching_mixed_rule() {
    let (ordinary, popup) = engines("||ads.example^$popup,script,domain=publisher.example\n||ads.example^$domain=publisher.example,script,popup,badfilter");
    assert!(!blocks(&popup, AD, PAGE, "document"));
    assert!(!blocks(&ordinary, AD, PAGE, "script"));
}

#[test]
fn badfilter_does_not_disable_a_projection_from_a_different_original_rule() {
    let (ordinary, popup) = engines("||ads.example^$popup,script\n||ads.example^$popup,badfilter\n||ads.example^$script,badfilter");
    assert!(blocks(&popup, AD, PAGE, "document"));
    assert!(blocks(&ordinary, AD, PAGE, "script"));
}

#[test]
fn important_and_mixed_exceptions_remain_upstream_owned() {
    let (ordinary, popup) = engines("||ads.example^$popup,script\n@@||ads.example^$popup,script");
    assert!(!blocks(&popup, AD, PAGE, "document"));
    assert!(!blocks(&ordinary, AD, PAGE, "script"));
    let (_, important) = engines("||ads.example^$popup,important\n@@||ads.example^$popup");
    assert!(blocks(&important, AD, PAGE, "document"));
}

#[test]
fn counts_track_original_accepted_rules_including_cosmetics() {
    let sets = build_rule_sets(
        "||ads.example^$popup,script\nexample.com##.ad\n||bad.example^$popup,unknown",
        ParseOptions::default(),
    );
    assert_eq!(sets.network_count, 1);
    assert_eq!(sets.cosmetic_count, 1);
    let ordinary = Engine::new_with_filter_set(sets.ordinary);
    assert!(ordinary
        .url_cosmetic_resources("https://example.com")
        .hide_selectors
        .contains(".ad"));
}

#[test]
fn c_abi_routes_only_explicit_popups_and_never_returns_navigation_responses() {
    use crate::*;
    let path = std::env::temp_dir().join(format!("aira-popup-ffi-{}.txt", std::process::id()));
    std::fs::write(
        &path,
        "||ads.example^$popup,redirect=empty\n||clean.example^$popup,removeparam=tracking",
    )
    .unwrap();
    let path_string = path.to_str().unwrap();
    let mut engine = std::ptr::null_mut();
    let status = unsafe {
        aira_adblock_engine_create_from_file(path_string.as_ptr(), path_string.len(), &mut engine)
    };
    std::fs::remove_file(path).unwrap();
    assert_eq!(status, STATUS_OK);
    assert!(!engine.is_null());
    for (url, request_type, expected_blocked) in [
        (AD, "popup", true),
        (AD, "document", false),
        (AD, "script", false),
        ("https://clean.example/?tracking=one", "popup", false),
    ] {
        let mut result = std::ptr::null_mut();
        let status = unsafe {
            aira_adblock_engine_check(
                engine,
                url.as_ptr(),
                url.len(),
                PAGE.as_ptr(),
                PAGE.len(),
                request_type.as_ptr(),
                request_type.len(),
                b"GET".as_ptr(),
                3,
                1,
                &mut result,
            )
        };
        assert_eq!(status, STATUS_OK);
        assert!(!result.is_null());
        let result_value = unsafe { &*result };
        assert_eq!(
            result_value.should_block, expected_blocked,
            "{url} {request_type}"
        );
        assert!(result_value.redirect_data_url.is_empty());
        assert!(result_value.rewritten_url.is_empty());
        assert!(result_value.csp_directives.is_empty());
        unsafe {
            aira_adblock_check_result_destroy(result);
        }
    }
    unsafe {
        aira_adblock_engine_destroy(engine);
    }
}
