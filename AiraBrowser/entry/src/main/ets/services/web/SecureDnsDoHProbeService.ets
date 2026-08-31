import { http } from '@kit.NetworkKit';

export interface SecureDnsDoHProbeCandidate {
  id: string;
  endpoint: string;
}

export interface SecureDnsDoHProbeResult {
  candidate: SecureDnsDoHProbeCandidate;
  reachable: boolean;
  elapsedMs: number;
}

const DNS_PROBE_QUERY: string = 'oXoBAAABAAAAAAAAB2V4YW1wbGUDY29tAAABAAE';
const DNS_PROBE_TRANSACTION_ID_HIGH: number = 0xA1;
const DNS_PROBE_TRANSACTION_ID_LOW: number = 0x7A;
const DNS_PROBE_TIMEOUT_MS: number = 1200;
const DNS_SELECTION_DEADLINE_MS: number = 1400;
const DNS_RESPONSE_MAX_BYTES: number = 64 * 1024;

export class SecureDnsDoHProbeService {
  async selectFirstReachable(
    candidates: SecureDnsDoHProbeCandidate[]
  ): Promise<SecureDnsDoHProbeResult | undefined> {
    if (candidates.length === 0) {
      return undefined;
    }
    return new Promise<SecureDnsDoHProbeResult | undefined>(
      (resolve: (result: SecureDnsDoHProbeResult | undefined) => void): void => {
        let completed: boolean = false;
        let pendingCount: number = candidates.length;
        let deadlineTimer: number = -1;
        const complete = (result: SecureDnsDoHProbeResult | undefined): void => {
          if (completed) {
            return;
          }
          completed = true;
          if (deadlineTimer >= 0) {
            clearTimeout(deadlineTimer);
          }
          resolve(result);
        };
        const handleUnavailable = (): void => {
          pendingCount -= 1;
          if (pendingCount <= 0) {
            complete(undefined);
          }
        };

        deadlineTimer = setTimeout((): void => {
          complete(undefined);
        }, DNS_SELECTION_DEADLINE_MS);

        for (let i = 0; i < candidates.length; i++) {
          const candidate = candidates[i];
          this.probe(candidate)
            .then((result: SecureDnsDoHProbeResult): void => {
              if (result.reachable) {
                complete(result);
                return;
              }
              handleUnavailable();
            })
            .catch((_error: Error): void => {
              handleUnavailable();
            });
        }
      }
    );
  }

  private async probe(candidate: SecureDnsDoHProbeCandidate): Promise<SecureDnsDoHProbeResult> {
    const request = http.createHttp();
    const startedAt = Date.now();
    try {
      const response = await request.request(this.buildProbeUrl(candidate.endpoint), {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: DNS_PROBE_TIMEOUT_MS,
        readTimeout: DNS_PROBE_TIMEOUT_MS,
        usingCache: false,
        usingProxy: false,
        maxLimit: DNS_RESPONSE_MAX_BYTES,
        header: {
          'Accept': 'application/dns-message',
          'User-Agent': 'AiraBrowser/1.0'
        }
      });
      const bytes = response.result instanceof ArrayBuffer ?
        new Uint8Array(response.result) : new Uint8Array();
      return {
        candidate: this.copyCandidate(candidate),
        reachable: response.responseCode === 200 && this.isValidDnsResponse(bytes),
        elapsedMs: Date.now() - startedAt
      };
    } catch (_error) {
      return {
        candidate: this.copyCandidate(candidate),
        reachable: false,
        elapsedMs: Date.now() - startedAt
      };
    } finally {
      request.destroy();
    }
  }

  private buildProbeUrl(endpoint: string): string {
    const separator = endpoint.includes('?') ? '&' : '?';
    return endpoint + separator + 'dns=' + DNS_PROBE_QUERY;
  }

  private isValidDnsResponse(bytes: Uint8Array): boolean {
    if (bytes.length < 12) {
      return false;
    }
    const transactionMatches = bytes[0] === DNS_PROBE_TRANSACTION_ID_HIGH &&
      bytes[1] === DNS_PROBE_TRANSACTION_ID_LOW;
    const isResponse = (bytes[2] & 0x80) !== 0;
    const hasSingleQuestion = bytes[4] === 0 && bytes[5] === 1;
    return transactionMatches && isResponse && hasSingleQuestion;
  }

  private copyCandidate(candidate: SecureDnsDoHProbeCandidate): SecureDnsDoHProbeCandidate {
    return {
      id: candidate.id,
      endpoint: candidate.endpoint
    };
  }
}
