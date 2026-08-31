import { util } from '@kit.ArkTS';
import { cert } from '@kit.DeviceCertificateKit';
import { BrowserRuntimeLifecyclePort } from './BrowserRuntimeLifecyclePort';

export interface SiteCertificatePresentationRuntimeContext {
  controllerAttached: boolean;
  secureCurrentSite: boolean;
  currentSiteHost: string;
}

export interface SiteCertificatePresentationState {
  summary: string;
  detailStatus: string;
  subject: string;
  issuer: string;
  validFrom: string;
  validTo: string;
  serialNumber: string;
  signatureAlgorithm: string;
  chainCount: number;
}

const SITE_CERTIFICATE_LOADING_TEXT: string = '正在读取证书信息...';
const SITE_CERTIFICATE_READY_STATUS: string = '连接安全，证书已读取';

export class SiteCertificatePresentationService {
  buildLoadingState(): SiteCertificatePresentationState {
    return this.buildState(SITE_CERTIFICATE_LOADING_TEXT, SITE_CERTIFICATE_LOADING_TEXT);
  }

  async resolveCurrentStateFromLifecyclePort(
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    context: SiteCertificatePresentationRuntimeContext
  ): Promise<SiteCertificatePresentationState> {
    if (!context.controllerAttached) {
      return this.buildUnavailableState('网页还未加载完成');
    }
    if (!context.secureCurrentSite) {
      return this.buildUnavailableState('当前连接未使用 HTTPS');
    }

    const controller = runtimeLifecyclePort.resolveActiveController();
    if (controller === undefined) {
      return this.buildUnavailableState('证书信息读取失败');
    }
    try {
      const certificates = await controller.getCertificate();
      if (certificates.length === 0) {
        return this.buildUnavailableState('未读取到证书信息');
      }
      return this.buildLoadedState(certificates[0], certificates.length, context.currentSiteHost);
    } catch (_error) {
      return this.buildUnavailableState('证书信息读取失败');
    }
  }

  buildUnavailableState(status: string): SiteCertificatePresentationState {
    return this.buildState(status, status);
  }

  buildLoadedState(
    certificate: cert.X509Cert,
    chainLength: number,
    fallbackSubject: string
  ): SiteCertificatePresentationState {
    const issuer = this.readCertificateIssuer(certificate);
    const validTo = this.formatCertificateDate(this.readCertificateNotAfterTime(certificate));
    return {
      summary: this.buildCertificateSummary(issuer, validTo, chainLength),
      detailStatus: SITE_CERTIFICATE_READY_STATUS,
      subject: this.readCertificateSubject(certificate, fallbackSubject),
      issuer: issuer,
      validFrom: this.formatCertificateDate(this.readCertificateNotBeforeTime(certificate)),
      validTo: validTo,
      serialNumber: this.readCertificateSerialNumber(certificate),
      signatureAlgorithm: this.readCertificateSignatureAlgorithm(certificate),
      chainCount: chainLength
    };
  }

  buildChainDetailText(chainCount: number): string {
    if (chainCount <= 0) {
      return '';
    }
    return `共 ${chainCount} 个证书`;
  }

  private buildState(summary: string, detailStatus: string): SiteCertificatePresentationState {
    return {
      summary: summary,
      detailStatus: detailStatus,
      subject: '',
      issuer: '',
      validFrom: '',
      validTo: '',
      serialNumber: '',
      signatureAlgorithm: '',
      chainCount: 0
    };
  }

  private buildCertificateSummary(issuer: string, validUntil: string, chainLength: number): string {
    const chainText = chainLength > 1 ? `，证书链 ${chainLength} 个` : '';
    if (issuer.length > 0 && validUntil.length > 0) {
      return `由 ${issuer} 签发，有效至 ${validUntil}${chainText}`;
    }
    if (validUntil.length > 0) {
      return `证书有效至 ${validUntil}${chainText}`;
    }
    if (issuer.length > 0) {
      return `由 ${issuer} 签发${chainText}`;
    }
    return `证书已读取${chainText}`;
  }

  private readCertificateIssuer(certificate: cert.X509Cert): string {
    try {
      return this.extractCertificateCommonName(certificate.getIssuerName(cert.EncodingType.ENCODING_UTF8));
    } catch (_error) {
      return '';
    }
  }

  private readCertificateSubject(certificate: cert.X509Cert, fallbackSubject: string): string {
    try {
      return this.extractCertificateCommonName(
        this.decodeCertificateData(certificate.getSubjectName(cert.EncodingType.ENCODING_UTF8))
      );
    } catch (_error) {
      return fallbackSubject;
    }
  }

  private decodeCertificateData(data: cert.DataBlob): string {
    try {
      return util.TextDecoder.create('utf-8').decodeToString(data.data).trim();
    } catch (_error) {
      return '';
    }
  }

  private readCertificateNotBeforeTime(certificate: cert.X509Cert): string {
    try {
      return certificate.getNotBeforeTime();
    } catch (_error) {
      return '';
    }
  }

  private readCertificateNotAfterTime(certificate: cert.X509Cert): string {
    try {
      return certificate.getNotAfterTime();
    } catch (_error) {
      return '';
    }
  }

  private readCertificateSerialNumber(certificate: cert.X509Cert): string {
    try {
      return certificate.getCertSerialNumber().toString();
    } catch (_error) {
      return '';
    }
  }

  private readCertificateSignatureAlgorithm(certificate: cert.X509Cert): string {
    try {
      return certificate.getSignatureAlgName();
    } catch (_error) {
      return '';
    }
  }

  private extractCertificateCommonName(name: string): string {
    const commonNameMatch = name.match(/(?:^|,)\s*CN\s*=\s*([^,]+)/i);
    if (commonNameMatch !== null) {
      return commonNameMatch[1].trim();
    }
    const organizationMatch = name.match(/(?:^|,)\s*O\s*=\s*([^,]+)/i);
    if (organizationMatch !== null) {
      return organizationMatch[1].trim();
    }
    return name.trim();
  }

  private formatCertificateDate(value: string): string {
    const match = value.match(/^(\d{4})[-/年]?(\d{1,2})[-/月]?(\d{1,2})/);
    if (match !== null) {
      return `${match[1]}-${this.padTwoDigits(match[2])}-${this.padTwoDigits(match[3])}`;
    }
    return value.trim();
  }

  private padTwoDigits(value: string): string {
    return value.length >= 2 ? value : `0${value}`;
  }
}
