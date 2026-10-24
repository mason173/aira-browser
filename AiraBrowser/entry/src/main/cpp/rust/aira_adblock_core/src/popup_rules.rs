use adblock::lists::{parse_filter, FilterSet, ParseOptions, ParsedLine};
use std::collections::HashSet;

// Upstream 0.13.2 has no popup request type. Keep this compatibility projection entirely in
// Rust: the normal engine must never see a popup-only rule as a document rule. The second
// FilterSet is queried only for explicit popup checks, with `document` as an internal carrier.
// URL patterns, exceptions, domains, party restrictions and modifiers still use upstream parsing.
// https://help.adblockplus.org/hc/en-us/articles/360062733293-How-to-write-filters
// https://github.com/gorhill/uBlock/wiki/Static-filter-syntax#all
pub(crate) struct RuleSets {
    pub ordinary: FilterSet,
    pub popup: FilterSet,
    pub network_count: usize,
    pub cosmetic_count: usize,
}

#[derive(Clone, Copy, Eq, Hash, PartialEq)]
struct RuleIdentity(Option<u64>, Option<u64>);

struct NetworkRule {
    ordinary: Option<String>,
    popup: Option<String>,
    identity: RuleIdentity,
    badfilter: bool,
}

pub(crate) fn build_rule_sets(rules: &str, options: ParseOptions) -> RuleSets {
    let mut ordinary_rules = String::new();
    let mut popup_rules = String::new();
    let mut network_rules = Vec::new();
    let mut disabled_rules = HashSet::new();
    let mut cosmetic_count = 0;
    for line in rules.lines().map(str::trim) {
        let projected = match project_popup_rule(line, options) {
            Some(projected) => projected,
            None => match parse_filter(line, false, options) {
                Ok(ParsedLine::Network(rule)) => Some(NetworkRule {
                    ordinary: Some(line.to_owned()),
                    popup: None,
                    identity: RuleIdentity(Some(rule.get_id()), None),
                    badfilter: rule.is_badfilter(),
                }),
                Ok(ParsedLine::Cosmetic(_)) => {
                    cosmetic_count += 1;
                    ordinary_rules.push_str(line);
                    ordinary_rules.push('\n');
                    None
                }
                Err(_) => None,
            },
        };
        if let Some(rule) = projected {
            if rule.badfilter {
                disabled_rules.insert(rule.identity);
            }
            network_rules.push(rule);
        }
    }
    // Resolve badfilter before splitting. Otherwise `foo$popup,badfilter` could accidentally
    // disable the popup half of the distinct rule `foo$popup,script` after projection.
    let network_count = network_rules.len();
    for rule in network_rules {
        if rule.badfilter || disabled_rules.contains(&rule.identity) {
            continue;
        }
        if let Some(line) = rule.ordinary {
            ordinary_rules.push_str(&line);
            ordinary_rules.push('\n');
        }
        if let Some(line) = rule.popup {
            popup_rules.push_str(&line);
            popup_rules.push('\n');
        }
    }
    let mut ordinary = FilterSet::new(false);
    ordinary.add_filter_list(ordinary_rules, options);
    let mut popup = FilterSet::new(false);
    popup.add_filter_list(popup_rules, options);
    RuleSets {
        ordinary,
        popup,
        network_count,
        cosmetic_count,
    }
}

// None means an unmodified upstream rule; Some(None) means an invalid compatibility rule.
fn project_popup_rule(line: &str, options: ParseOptions) -> Option<Option<NetworkRule>> {
    // Match the pinned upstream parser's option boundary and comma tokenization. Parsing the
    // validation candidate below also excludes comments, cosmetic rules and unsupported syntax.
    let (pattern, raw_options) = line.rsplit_once('$')?;
    let tokens: Vec<&str> = raw_options.split(',').collect();
    let has_popup = tokens.contains(&"popup");
    let excludes_popup = tokens.contains(&"~popup");
    let has_all = tokens.contains(&"all");
    if !has_popup && !excludes_popup && !has_all {
        return None;
    }

    let validation_options: Vec<&str> = tokens
        .iter()
        .filter_map(|token| match *token {
            "popup" => Some("document"),
            "~popup" => None,
            value => Some(value),
        })
        .collect();
    let validation = with_options(pattern, &validation_options);
    let Ok(ParsedLine::Network(validated)) = parse_filter(&validation, false, options) else {
        return Some(None);
    };
    let badfilter = validated.is_badfilter();
    let mut ordinary_options: Vec<&str> = tokens
        .iter()
        .copied()
        .filter(|token| *token != "popup" && *token != "~popup")
        .collect();
    // A positive popup type alone does not imply any ordinary request types. Negated network
    // types do imply ordinary network types, as in upstream's `$popup,~script` semantics.
    let has_ordinary_types = ordinary_options.iter().any(|token| is_content_type(token));
    // Do not turn `||host^$~popup` into a bare hostname rule: upstream gives bare hostnames
    // implicit strict document blocking. A negated popup type only implies network types.
    // CSP and removeparam have their own upstream default request types. In particular, adding
    // network types would expand removeparam to scripts/images and remove it from documents.
    if excludes_popup
        && !has_popup
        && !has_ordinary_types
        && !validated.is_csp()
        && !validated.is_removeparam()
    {
        ordinary_options.extend([
            "image",
            "media",
            "object",
            "other",
            "ping",
            "script",
            "stylesheet",
            "subdocument",
            "xmlhttprequest",
            "websocket",
            "font",
        ]);
    }
    let ordinary = if !has_popup || has_ordinary_types {
        Some(with_options(pattern, &ordinary_options))
    } else {
        None
    };
    let popup = if (has_popup || has_all) && !excludes_popup {
        let mut popup_options: Vec<&str> = ordinary_options
            .iter()
            .copied()
            .filter(|token| !is_content_type(token))
            .collect();
        popup_options.push("document");
        Some(with_options(pattern, &popup_options))
    } else {
        None
    };
    let mut identity = RuleIdentity(None, None);
    for (projection, id) in [(&ordinary, &mut identity.0), (&popup, &mut identity.1)] {
        if let Some(projection) = projection {
            let Ok(ParsedLine::Network(rule)) = parse_filter(projection, false, options) else {
                return Some(None);
            };
            *id = Some(rule.get_id());
        }
    }
    Some(Some(NetworkRule {
        ordinary,
        popup,
        identity,
        badfilter,
    }))
}

fn with_options(pattern: &str, options: &[&str]) -> String {
    if options.is_empty() {
        pattern.to_owned()
    } else {
        format!("{pattern}${}", options.join(","))
    }
}

fn is_content_type(option: &str) -> bool {
    matches!(
        option.strip_prefix('~').unwrap_or(option),
        "document"
            | "doc"
            | "image"
            | "media"
            | "object"
            | "object-subrequest"
            | "other"
            | "ping"
            | "beacon"
            | "script"
            | "stylesheet"
            | "css"
            | "subdocument"
            | "frame"
            | "xmlhttprequest"
            | "xhr"
            | "websocket"
            | "font"
            | "all"
    )
}

#[cfg(test)]
#[path = "popup_rules_tests.rs"]
mod tests;
