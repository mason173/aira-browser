import { util } from '@kit.ArkTS';
import zlib from '@ohos.zlib';

const HUAWEI_SPACE_SNAPSHOT_BLOB_MAGIC: Uint8Array = new Uint8Array([
  0x41, 0x49, 0x52, 0x41, 0x48, 0x53, 0x42, 0x31
]);
const HUAWEI_SPACE_SNAPSHOT_BLOB_HEADER_BYTES: number = 12;
const HUAWEI_SPACE_SNAPSHOT_BLOB_MAX_STORED_BYTES: number = 1800000;
const HUAWEI_SPACE_SNAPSHOT_JSON_MAX_BYTES: number = 64 * 1024 * 1024;

export class HuaweiSpaceSnapshotBlobCodec {
  private encoder: util.TextEncoder = util.TextEncoder.create('utf-8');
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8');

  async encodeJson(json: string): Promise<Uint8Array> {
    const source = this.encoder.encodeInto(json);
    if (source.byteLength <= 0 || source.byteLength > HUAWEI_SPACE_SNAPSHOT_JSON_MAX_BYTES) {
      throw new Error('华为云空间快照原始数据大小无效。');
    }
    const zip = await zlib.createZip();
    const compressedBound = await zip.compressBound(source.byteLength);
    const compressedBuffer = new ArrayBuffer(compressedBound);
    const sourceBuffer = source.buffer.slice(source.byteOffset, source.byteOffset + source.byteLength);
    const result = await zip.compress2(
      compressedBuffer,
      sourceBuffer,
      zlib.CompressLevel.COMPRESS_LEVEL_BEST_COMPRESSION,
      source.byteLength
    );
    if (result.status !== zlib.ReturnStatus.OK || result.destLen <= 0) {
      throw new Error('华为云空间快照压缩失败。');
    }
    const payloadLength = HUAWEI_SPACE_SNAPSHOT_BLOB_HEADER_BYTES + result.destLen;
    if (payloadLength > HUAWEI_SPACE_SNAPSHOT_BLOB_MAX_STORED_BYTES) {
      throw new Error('华为云空间快照压缩后仍超过关系型数据库单行安全上限。');
    }
    const payload = new Uint8Array(payloadLength);
    payload.set(HUAWEI_SPACE_SNAPSHOT_BLOB_MAGIC, 0);
    this.writeUint32(payload, HUAWEI_SPACE_SNAPSHOT_BLOB_MAGIC.byteLength, source.byteLength);
    payload.set(
      new Uint8Array(compressedBuffer, 0, result.destLen),
      HUAWEI_SPACE_SNAPSHOT_BLOB_HEADER_BYTES
    );
    return payload;
  }

  async decodeJson(payload: Uint8Array): Promise<string> {
    if (payload.byteLength < HUAWEI_SPACE_SNAPSHOT_BLOB_HEADER_BYTES ||
      payload.byteLength > HUAWEI_SPACE_SNAPSHOT_BLOB_MAX_STORED_BYTES ||
      !this.hasExpectedMagic(payload)) {
      throw new Error('华为云空间快照二进制格式无效。');
    }
    const sourceLength = this.readUint32(payload, HUAWEI_SPACE_SNAPSHOT_BLOB_MAGIC.byteLength);
    if (sourceLength <= 0 || sourceLength > HUAWEI_SPACE_SNAPSHOT_JSON_MAX_BYTES) {
      throw new Error('华为云空间快照解压大小无效。');
    }
    const compressedLength = payload.byteLength - HUAWEI_SPACE_SNAPSHOT_BLOB_HEADER_BYTES;
    const compressedBuffer = payload.buffer.slice(
      payload.byteOffset + HUAWEI_SPACE_SNAPSHOT_BLOB_HEADER_BYTES,
      payload.byteOffset + payload.byteLength
    );
    const outputBuffer = new ArrayBuffer(sourceLength);
    const zip = await zlib.createZip();
    const result = await zip.uncompress(outputBuffer, compressedBuffer, compressedLength);
    if (result.status !== zlib.ReturnStatus.OK || result.destLen !== sourceLength) {
      throw new Error('华为云空间快照解压失败。');
    }
    return this.decoder.decodeToString(new Uint8Array(outputBuffer, 0, result.destLen));
  }

  private hasExpectedMagic(payload: Uint8Array): boolean {
    for (let index = 0; index < HUAWEI_SPACE_SNAPSHOT_BLOB_MAGIC.byteLength; index += 1) {
      if (payload[index] !== HUAWEI_SPACE_SNAPSHOT_BLOB_MAGIC[index]) {
        return false;
      }
    }
    return true;
  }

  private writeUint32(target: Uint8Array, offset: number, value: number): void {
    target[offset] = Math.floor(value / 0x1000000) % 0x100;
    target[offset + 1] = Math.floor(value / 0x10000) % 0x100;
    target[offset + 2] = Math.floor(value / 0x100) % 0x100;
    target[offset + 3] = value % 0x100;
  }

  private readUint32(source: Uint8Array, offset: number): number {
    return source[offset] * 0x1000000 + source[offset + 1] * 0x10000 +
      source[offset + 2] * 0x100 + source[offset + 3];
  }
}
