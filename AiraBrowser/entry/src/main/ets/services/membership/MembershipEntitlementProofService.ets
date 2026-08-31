import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import {
  AiraMembershipEntitlementClaims,
  AiraSubscriptionStatus
} from '../../common/models/MembershipModels';

const MEMBERSHIP_ENTITLEMENT_KEY_ID: string = 'aira-entitlement-rsa-20260723';
const MEMBERSHIP_ENTITLEMENT_ISSUER: string = 'aira-api';
const MEMBERSHIP_ENTITLEMENT_PROOF_VERSION: number = 1;
const MEMBERSHIP_ENTITLEMENT_CLOCK_SKEW_MS: number = 5 * 60 * 1000;
const MEMBERSHIP_ENTITLEMENT_PROOF_MAX_CHARS: number = 16384;
const MEMBERSHIP_ENTITLEMENT_PUBLIC_KEY_PEM: string =
  '-----BEGIN PUBLIC KEY-----\n' +
  'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAzJ/bW3WytA5QOR1w1vqS\n' +
  '5yAMhpaloKYrybgT28q6ZpC2evSFlOXEn0TGOEM9MAXLIKoWLBJrCbt9zQea0wNk\n' +
  'OabJsQaQou0trSu+r5oUUm4vVJ4vmz5CjSYBMxJww6+uDmCnEtmJnndq9+bpcnfM\n' +
  'Au273QeWFIAOsJatrepf18HlIaotRRLxfoQNorGRWQiQQuYm6p3D74an8Yazdeyq\n' +
  '6+2WT/neZzxS/TtoVQsAh/gdh96iQ3Pl7XNFSOT1I+obI41ZEruGtSqZHz23wLjJ\n' +
  'AMFOcFGZcQWCSt/spSynukWdL0tf3k6vMjnbYiAtXq8KKR5VirI6HcMQlTKv8l9p\n' +
  'bQIDAQAB\n' +
  '-----END PUBLIC KEY-----';

interface MembershipEntitlementProofHeader {
  alg: string;
  typ: string;
  kid: string;
}

export interface MembershipEntitlementProofVerificationResult {
  valid: boolean;
  reason: string;
  claims?: AiraMembershipEntitlementClaims;
}

export class MembershipEntitlementProofService {
  private encoder: util.TextEncoder = util.TextEncoder.create('utf-8');
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
  private base64Helper: util.Base64Helper = new util.Base64Helper();
  private cachedProof: string = '';
  private cachedUid: string = '';
  private cachedResult?: MembershipEntitlementProofVerificationResult;

  verify(
    proof: string,
    expectedUid: string,
    now: number = Date.now()
  ): MembershipEntitlementProofVerificationResult {
    const normalizedProof = proof.trim();
    const normalizedUid = expectedUid.trim();
    const cached = this.cachedResult;
    if (normalizedProof === this.cachedProof && normalizedUid === this.cachedUid && cached?.valid === true &&
      (cached.claims?.issuedAt ?? 0) <= now + MEMBERSHIP_ENTITLEMENT_CLOCK_SKEW_MS &&
      (cached.claims?.offlineUntil ?? 0) > now) {
      return cached;
    }
    const result = this.verifyUncached(normalizedProof, normalizedUid, now);
    this.cachedProof = normalizedProof;
    this.cachedUid = normalizedUid;
    this.cachedResult = result;
    return result;
  }

  private verifyUncached(
    proof: string,
    expectedUid: string,
    now: number
  ): MembershipEntitlementProofVerificationResult {
    if (proof.length <= 0 || proof.length > MEMBERSHIP_ENTITLEMENT_PROOF_MAX_CHARS || expectedUid.length <= 0) {
      return this.invalid('missing_or_oversized');
    }
    const segments = proof.split('.');
    if (segments.length !== 3 || segments.some((segment: string): boolean => segment.length <= 0)) {
      return this.invalid('invalid_compact_format');
    }
    try {
      const header = this.parseHeader(segments[0]);
      if (header.alg !== 'RS256' || header.typ !== 'JWT' || header.kid !== MEMBERSHIP_ENTITLEMENT_KEY_ID) {
        return this.invalid('unsupported_header');
      }
      const signingInput = `${segments[0]}.${segments[1]}`;
      if (!this.verifySignature(signingInput, segments[2])) {
        return this.invalid('signature_mismatch');
      }
      const claims = this.parseClaims(segments[1]);
      if (claims.v !== MEMBERSHIP_ENTITLEMENT_PROOF_VERSION || claims.kid !== MEMBERSHIP_ENTITLEMENT_KEY_ID ||
        claims.iss !== MEMBERSHIP_ENTITLEMENT_ISSUER || claims.sub !== expectedUid || claims.plan !== 'pro') {
        return this.invalid('claims_mismatch');
      }
      if (claims.issuedAt <= 0 || claims.issuedAt > now + MEMBERSHIP_ENTITLEMENT_CLOCK_SKEW_MS ||
        claims.offlineUntil <= claims.issuedAt || claims.offlineUntil <= now) {
        return this.invalid('outside_offline_window');
      }
      if (claims.grantExpiresAt > 0 && claims.offlineUntil < claims.grantExpiresAt) {
        return this.invalid('invalid_expiry_window');
      }
      return {
        valid: true,
        reason: 'verified',
        claims
      };
    } catch (_error) {
      return this.invalid('malformed_proof');
    }
  }

  private parseHeader(segment: string): MembershipEntitlementProofHeader {
    const raw = JSON.parse(this.decodeSegment(segment)) as Record<string, string | undefined>;
    return {
      alg: `${raw.alg ?? ''}`.trim(),
      typ: `${raw.typ ?? ''}`.trim(),
      kid: `${raw.kid ?? ''}`.trim()
    };
  }

  private parseClaims(segment: string): AiraMembershipEntitlementClaims {
    const raw = JSON.parse(this.decodeSegment(segment)) as Record<string, string | number | undefined>;
    const subscriptionStatus = this.normalizeSubscriptionStatus(raw.subscriptionStatus);
    const accountRecognition = raw.accountRecognition === 'aira_insider' ? 'aira_insider' : 'none';
    return {
      v: this.normalizeInteger(raw.v),
      kid: this.normalizeString(raw.kid),
      iss: this.normalizeString(raw.iss),
      sub: this.normalizeString(raw.sub),
      plan: raw.plan === 'pro' ? 'pro' : 'guest',
      source: this.normalizeString(raw.source),
      productId: this.normalizeString(raw.productId),
      subscriptionStatus,
      accountRecognition,
      grantExpiresAt: this.normalizeTimestamp(raw.grantExpiresAt),
      issuedAt: this.normalizeTimestamp(raw.issuedAt),
      offlineUntil: this.normalizeTimestamp(raw.offlineUntil)
    };
  }

  private verifySignature(signingInput: string, signatureSegment: string): boolean {
    const keyGenerator = cryptoFramework.createAsyKeyGenerator('RSA2048');
    const keyPair = keyGenerator.convertPemKeySync(MEMBERSHIP_ENTITLEMENT_PUBLIC_KEY_PEM, null);
    const verifier = cryptoFramework.createVerify('RSA2048|PKCS1|SHA256');
    verifier.initSync(keyPair.pubKey);
    verifier.updateSync({ data: this.encoder.encodeInto(signingInput) });
    return verifier.verifySync(null, { data: this.decodeBase64Url(signatureSegment) });
  }

  private decodeSegment(value: string): string {
    return this.decoder.decodeToString(this.decodeBase64Url(value));
  }

  private decodeBase64Url(value: string): Uint8Array {
    let padded = value;
    while (padded.length % 4 !== 0) {
      padded += '=';
    }
    return this.base64Helper.decodeSync(padded, util.Type.BASIC_URL_SAFE);
  }

  private normalizeSubscriptionStatus(value: string | number | undefined): AiraSubscriptionStatus {
    if (value === 'active' || value === 'grace_period' || value === 'expired' || value === 'cancelled' ||
      value === 'unknown') {
      return value;
    }
    return 'none';
  }

  private normalizeString(value: string | number | undefined): string {
    return `${value ?? ''}`.trim();
  }

  private normalizeInteger(value: string | number | undefined): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.floor(value));
  }

  private normalizeTimestamp(value: string | number | undefined): number {
    return this.normalizeInteger(value);
  }

  private invalid(reason: string): MembershipEntitlementProofVerificationResult {
    return {
      valid: false,
      reason
    };
  }
}
