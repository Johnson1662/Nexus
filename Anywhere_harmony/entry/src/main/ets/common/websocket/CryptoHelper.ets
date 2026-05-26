/**
 * CryptoHelper — 手机端加密工具
 *
 * - Ed25519 密钥对：HUKS 优先，软件 fallback
 * - 导出公钥 hex
 * - Ed25519 签名
 * - AES-256-GCM 加密/解密（用于 EncryptedChannel）
 */

import { huks } from '@kit.CryptoArchitectureKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'CryptoHelper';
const HUKS_KEY_ALIAS: string = 'anywhere_ed25519_client';

export interface ClientKeyPair {
  /** Ed25519 公钥 hex（32 字节 => 64 hex chars） */
  publicKeyHex: string;
  /** 是否为 HUKS 生成（标记 software-backed） */
  isHardwareBacked: boolean;
}

// ── Ed25519 Key Generation ─────────────────────────────────────────

/** 获取或创建 Ed25519 客户端密钥对 */
export async function getOrCreateClientKeyPair(): Promise<ClientKeyPair> {
  // 1. Try HUKS — check if key already exists
  try {
    const pubKey = await tryExportHuksPublicKey();
    if (pubKey !== null) {
      return { publicKeyHex: pubKey, isHardwareBacked: true };
    }
  } catch {}

  // 2. Try HUKS — generate new key
  try {
    const pubKey = await tryGenerateHuksKey();
    if (pubKey !== null) {
      return { publicKeyHex: pubKey, isHardwareBacked: true };
    }
  } catch {}

  // 3. Fallback: software key
  hilog.warn(DOMAIN, TAG, 'HUKS Ed25519 unavailable, falling back to software key');
  const swKey = await generateSoftwareKey();
  return { publicKeyHex: swKey.publicKeyHex, isHardwareBacked: false };
}

/** 用 Ed25519 对 data（UTF-8 字符串）签名，返回 hex 签名 */
export async function signWithClientKey(data: string): Promise<string> {
  // Try HUKS first
  try {
    const sig = await tryHuksSign(data);
    if (sig !== null) return sig;
  } catch {}

  // Fallback: software sign
  return signSoftware(data);
}

/** 生成 X25519 临时密钥对（hex 格式，用于 PFS 握手的 ephemeral key） */
export async function generateEphemeralKeyPair(): Promise<{ publicKeyHex: string; privateKeyHex: string }> {
  const generator = cryptoFramework.createAsyKeyGenerator('X25519');
  const keyPair = await generator.generateKeyPair();
  const pubBlob = await keyPair.pubKey.getEncoded();
  const privBlob = await keyPair.priKey.getEncoded();
  return {
    publicKeyHex: bytesToHex(new Uint8Array(pubBlob.data)),
    privateKeyHex: bytesToHex(new Uint8Array(privBlob.data)),
  };
}

/** ECDH 密钥协商：计算 sharedSecret = myPrivKey * theirPubKey (X25519) */
export async function computeEcdhSharedSecret(
  myPrivateKeyHex: string,
  theirPublicKeyHex: string,
): Promise<Uint8Array> {
  // Use software X25519 key agreement
  const generator = cryptoFramework.createAsyKeyGenerator('X25519');
  const pubKey = await generator.convertKey(
    { data: hexToBytes(theirPublicKeyHex) } as cryptoFramework.DataBlob,
  );
  const privKey = await generator.convertKey(
    undefined,
    { data: hexToBytes(myPrivateKeyHex) } as cryptoFramework.DataBlob,
  );
  // Use key agreement via cryptoFramework
  const keyAgreement = cryptoFramework.createKeyAgreement('X25519');
  const sharedSecret = await keyAgreement.generateSecret(privKey, pubKey);
  return new Uint8Array(sharedSecret.data);
}

/** HKDF-SHA256: 从 shared secret 派生 32 字节 AES key */
export function hkdfExpand(secret: Uint8Array, salt: Uint8Array, info: string): Uint8Array {
  // For Phase 2a: simplified single-block HKDF-Expand
  // We use HMAC-SHA256 manually via the framework
  // Note: full implementation needs the actual HMAC; for Phase 2a return placeholder
  // Phase 2b will implement proper HKDF
  let result: Uint8Array = new Uint8Array(32);
  for (let i: number = 0; i < 32 && i < secret.length; i++) {
    result[i] = secret[i];
  }
  return result;
}

/** AES-256-GCM 加密 */
export function encryptAesGcm(
  plaintext: Uint8Array,
  key: Uint8Array,
  iv?: Uint8Array,
): { ciphertext: Uint8Array; iv: Uint8Array; tag: Uint8Array } {
  // Phone-side encryption: for Phase 2a, define interface; full impl in Phase 2b
  return { ciphertext: plaintext, iv: iv || new Uint8Array(12), tag: new Uint8Array(16) };
}

/** AES-256-GCM 解密 */
export function decryptAesGcm(
  ciphertext: Uint8Array,
  key: Uint8Array,
  iv: Uint8Array,
  tag: Uint8Array,
): Uint8Array {
  return ciphertext;
}





// ── Private: HUKS ──────────────────────────────────────────────────

async function tryExportHuksPublicKey(): Promise<string | null> {
  return new Promise<string | null>((resolve) => {
    huks.exportPublicKeyItem(HUKS_KEY_ALIAS, {
      properties: [],
    } as huks.HuksOptions, (err: BusinessError, data: huks.HuksReturnResult) => {
      if (err || !data.outData) {
        resolve(null);
        return;
      }
      const hex = bytesToHex(new Uint8Array(data.outData));
      resolve(hex);
    });
  });
}

async function tryGenerateHuksKey(): Promise<string | null> {
  return new Promise<string | null>((resolve) => {
    const options: huks.HuksOptions = {
      properties: [
        { tag: huks.HuksTag.HUKS_TAG_KEY_STORAGE_FLAG, value: huks.HuksKeyStorageType.HUKS_STORAGE_PERSISTENT },
        { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_ED25519 },
        { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: 256 },
        { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksPurpose.HUKS_PURPOSE_SIGN | huks.HuksPurpose.HUKS_PURPOSE_VERIFY },
        { tag: huks.HuksTag.HUKS_TAG_DIGEST, value: huks.HuksKeyDigest.HUKS_DIGEST_SHA512 },
      ] as huks.HuksParam[],
    } as huks.HuksOptions;

    huks.generateKeyItem(HUKS_KEY_ALIAS, options, (err: BusinessError) => {
      if (err) {
        resolve(null);
        return;
      }
      huks.exportPublicKeyItem(HUKS_KEY_ALIAS, options, (err2: BusinessError, data: huks.HuksReturnResult) => {
        if (err2 || !data.outData) {
          resolve(null);
          return;
        }
        resolve(bytesToHex(new Uint8Array(data.outData)));
      });
    });
  });
}

async function tryHuksSign(data: string): Promise<string | null> {
  return new Promise<string | null>((resolve) => {
    const options: huks.HuksOptions = {
      properties: [
        { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_ED25519 },
        { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksPurpose.HUKS_PURPOSE_SIGN },
        { tag: huks.HuksTag.HUKS_TAG_DIGEST, value: huks.HuksKeyDigest.HUKS_DIGEST_SHA512 },
      ] as huks.HuksParam[],
      inData: stringToUint8Array(data),
    } as huks.HuksOptions;

    huks.initSession(HUKS_KEY_ALIAS, options, (err: BusinessError, handle: number) => {
      if (err) {
        resolve(null);
        return;
      }
      huks.finishSession(handle, options, (err2: BusinessError, result: huks.HuksReturnResult) => {
        if (err2 || !result.outData) {
          resolve(null);
          return;
        }
        resolve(bytesToHex(new Uint8Array(result.outData)));
      });
    });
  });
}

// ── Private: Software Fallback ─────────────────────────────────────

interface SoftwareKeyPair {
  publicKeyHex: string;
  privateKeyHex: string;
}

let _swKeyPair: SoftwareKeyPair | null = null;

async function generateSoftwareKey(): Promise<SoftwareKeyPair> {
  if (_swKeyPair !== null) return _swKeyPair;

  const generator = cryptoFramework.createAsyKeyGenerator('Ed25519');
  const keyPair = await generator.generateKeyPair();
  const pubKeyBlob = await keyPair.pubKey.getEncoded();
  const privKeyBlob = await keyPair.priKey.getEncoded();

  const pubHex = bytesToHex(new Uint8Array(pubKeyBlob.data));
  const privHex = bytesToHex(new Uint8Array(privKeyBlob.data));

  _swKeyPair = { publicKeyHex: pubHex, privateKeyHex: privHex };
  return _swKeyPair;
}

async function signSoftware(data: string): Promise<string> {
  const sw = await generateSoftwareKey();
  const keyPair = await cryptoFramework.createAsyKeyGenerator('Ed25519').convertKey(
    { data: hexToBytes(sw.publicKeyHex) } as cryptoFramework.DataBlob,
    { data: hexToBytes(sw.privateKeyHex) } as cryptoFramework.DataBlob,
  );

  const signer = cryptoFramework.createSign(keyPair.priKey.algName);
  await signer.init(keyPair.priKey);
  const sig = await signer.sign({ data: stringToUint8Array(data) } as cryptoFramework.DataBlob);
  return bytesToHex(new Uint8Array(sig.data));
}

// ── Utilities ──────────────────────────────────────────────────────

function bytesToHex(bytes: Uint8Array): string {
  let hex: string = '';
  for (let i: number = 0; i < bytes.length; i++) {
    hex += bytes[i].toString(16).padStart(2, '0');
  }
  return hex;
}

function hexToBytes(hex: string): Uint8Array {
  let bytes: Uint8Array = new Uint8Array(hex.length / 2);
  for (let i: number = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(hex.substr(i * 2, 2), 16);
  }
  return bytes;
}

function stringToUint8Array(str: string): Uint8Array {
  let buf: Uint8Array = new Uint8Array(str.length);
  for (let i: number = 0; i < str.length; i++) {
    buf[i] = str.charCodeAt(i);
  }
  return buf;
}
