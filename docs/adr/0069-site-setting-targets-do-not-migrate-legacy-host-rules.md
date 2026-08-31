# Site Setting Targets Do Not Migrate Legacy Host Rules

Accepted: 2026-08-07

## Context

Legacy single-site records identify a scheme and host but cannot recover the original port, and some records also carry
subdomain-expansion semantics. The new Site Setting Target is an exact Origin: scheme, host, and effective port. Mapping
old records to port 80 or 443 would guess user intent, while retaining legacy matching would silently restore the
host-wide behavior the new model removes.

## Decision

The exact-Origin site-rule store starts empty and does not read, migrate, or fall back to legacy host-scoped records.
Browser-wide UA settings and the Browsing Identity Catalog, including user-saved custom identities, remain intact.
New targets may be opened either from the current page or from the Site Controls management action, which accepts a
valid HTTP/HTTPS address including an IP/hostname and optional non-default port. The management form only navigates to
the target; it does not create an empty entry before the user saves a setting.

On first use of the new schema, the app performs an idempotent retirement cleanup of the old UA site-rule,
clear-on-close, site-permission, and external-navigation site-rule records. A failed cleanup may retry on a later start,
but legacy rules never participate in matching. The cleanup preserves browser-wide UA settings, the Browsing Identity
Catalog, global permission defaults, the global external-navigation policy, and separately managed Host Rules.

## Considered Options

- Converting legacy records to the scheme's default port was rejected because the lost original port cannot be inferred.
- Keeping legacy rules active until edited was rejected because it creates hidden host-wide matching beside the
  exact-Origin model.
- Leaving legacy records stored but permanently unread was rejected because obsolete internal-site configuration would
  remain on the device without serving a product purpose.

## Consequences

Users must configure single-site settings again after the exact-Origin model ships. The implementation may introduce a
new storage schema or key, but it must not add a compatibility reader, guessed conversion, or broad-match fallback for
the legacy records. A manually entered default port is normalized away while a non-default port remains part of the
canonical Origin, so another service on the same host opens a separate target. Downgrading to an older app build
cannot recover the retired single-site rules.
