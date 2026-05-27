/**
 * CryptoHelper — 手机端加密工具
 *
 * - Ed25519 密钥对：cryptoFramework 软件生成
 * - 导出公钥 hex
 * - Ed25519 签名
 * - AES-256-GCM 加密/解密
 *
 * ArkTS 严格模式注意事项：
 * - 所有 async callback API 用 Promise 封装时需显式类型标注
 * - Mac.doFinal 的 2 参数重载在 strict mode 中不可用，改用 update + doFinal
 * - 禁用 as any / as unknown 转型
 */

import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'CryptoHelper';

export interface ClientKeyPair {
  publicKeyHex: string;
  isHardwareBacked: boolean;
}

interface EphemeralKeyPair {
  publicKeyHex: string;
  privateKeyHex: string;
}

export interface HandshakeResult {
  aesKey: Uint8Array;
  channelIdHex: string;
}

export interface EncryptResult {
  ciphertext: Uint8Array;
  iv: Uint8Array;
  tag: Uint8Array;
}

interface SoftwareKeyPair {
  publicKeyHex: string;
  privateKeyHex: string;
}

// ── Module state ───────────────────────────────────────────────────

let _currentEphKeyPair: EphemeralKeyPair | null = null;
let _swKeyPair: SoftwareKeyPair | null = null;

// ── Ed25519 Key Generation (software only) ─────────────────────────

/** 获取或创建 Ed25519 客户端密钥对 */
export async function getOrCreateClientKeyPair(): Promise<ClientKeyPair> {
  const swKey: SoftwareKeyPair = await generateSoftwareKey();
  const result: ClientKeyPair = { publicKeyHex: swKey.publicKeyHex, isHardwareBacked: false };
  return result;
}

/** 用 Ed25519 对 data（UTF-8 字符串）签名，返回 hex 签名 */
export async function signWithClientKey(data: string): Promise<string> {
  return signSoftware(data);
}

/** 生成 X25519 临时密钥对（hex 格式，用于 PFS 握手的 ephemeral key） */
export async function generateEphemeralKeyPair(): Promise<EphemeralKeyPair> {
  const generator: cryptoFramework.AsyKeyGenerator = cryptoFramework.createAsyKeyGenerator('X25519');
  const keyPair: cryptoFramework.KeyPair = await generator.generateKeyPair();
  const pubBlob: cryptoFramework.DataBlob = await keyPair.pubKey.getEncoded();
  const privBlob: cryptoFramework.DataBlob = await keyPair.priKey.getEncoded();
  const ephPair: EphemeralKeyPair = {
    publicKeyHex: bytesToHex(new Uint8Array(pubBlob.data)),
    privateKeyHex: bytesToHex(new Uint8Array(privBlob.data)),
  };
  _currentEphKeyPair = ephPair;
  return _currentEphKeyPair;
}

/** 完成 E2EE 握手，验证服务端签名并派生 AES Key */
export async function finishE2EEHandshake(
  ephHostHex: string,
  hostSignatureHex: string,
  clientId: string
): Promise<HandshakeResult | null> {
  if (_currentEphKeyPair === null) throw new Error("No ephemeral key pair found");

  const hostEd25519PubKey: string = AppStorage.get<string>('hostEd25519PublicKey') || '';
  const hostId: string = AppStorage.get<string>('hostId') || '';

  // 1. Verify Host Signature: sign(hostId + ephHostHex + clientId)
  const signPayload: string = hostId + ephHostHex + clientId;

  try {
    const verifier: cryptoFramework.Verify = cryptoFramework.createVerify('Ed25519');
    const pubKeyGenerator: cryptoFramework.AsyKeyGenerator = cryptoFramework.createAsyKeyGenerator('Ed25519');
    const hostPubKeyData: cryptoFramework.DataBlob = { data: hexToBytes(hostEd25519PubKey) };
    const hostKeyPair: cryptoFramework.KeyPair = await keyPairFromPubKey(pubKeyGenerator, hostPubKeyData);
    await verifier.init(hostKeyPair.pubKey);
    const sigData: cryptoFramework.DataBlob = { data: stringToUint8Array(signPayload) };
    const keyData: cryptoFramework.DataBlob = { data: hexToBytes(hostSignatureHex) };
    const valid: boolean = await verifier.verify(sigData, keyData);
    if (!valid) {
      hilog.error(0x0, 'CryptoHelper', 'Host signature verification failed');
      return null;
    }
  } catch (err) {
    hilog.error(0x0, 'CryptoHelper', 'Host signature verification error: ' + JSON.stringify(err));
    return null;
  }

  // 2. Compute Shared Secret
  const sharedSecret: Uint8Array = await computeEcdhSharedSecret(_currentEphKeyPair.privateKeyHex, ephHostHex);

  // 3. Derive AES Key via HKDF
  const salt: Uint8Array = hexToBytes(_currentEphKeyPair.publicKeyHex).subarray(0, 16);
  const aesKey: Uint8Array = await hkdfExpand(sharedSecret, salt, 'anywhere-e2ee-v1');

  const channelIdHex: string = _currentEphKeyPair.publicKeyHex.substring(0, 16);

  const result: HandshakeResult = { aesKey: aesKey, channelIdHex: channelIdHex };
  return result;
}

/** ECDH 密钥协商：计算 sharedSecret = myPrivKey * theirPubKey (X25519) */
export async function computeEcdhSharedSecret(
  myPrivateKeyHex: string,
  theirPublicKeyHex: string,
): Promise<Uint8Array> {
  const generator: cryptoFramework.AsyKeyGenerator = cryptoFramework.createAsyKeyGenerator('X25519');
  const emptyData: cryptoFramework.DataBlob = { data: new Uint8Array(0) };
  const myPrivData: cryptoFramework.DataBlob = { data: hexToBytes(myPrivateKeyHex) };
  const myKeyPair: cryptoFramework.KeyPair = await keyPairFromPubAndPriv(generator, emptyData, myPrivData);
  const theirPubData: cryptoFramework.DataBlob = { data: hexToBytes(theirPublicKeyHex) };
  const theirKeyPair: cryptoFramework.KeyPair = await keyPairFromPubKey(generator, theirPubData);
  const keyAgreement: cryptoFramework.KeyAgreement = cryptoFramework.createKeyAgreement('X25519');
  const sharedSecret: cryptoFramework.DataBlob = await keyAgreement.generateSecret(myKeyPair.priKey, theirKeyPair.pubKey);
  return new Uint8Array(sharedSecret.data);
}

/** HKDF-SHA256: 从 shared secret 派生 32 字节 AES key */
export async function hkdfExpand(secret: Uint8Array, salt: Uint8Array, info: string): Promise<Uint8Array> {
  // Step 1: PRK = HMAC-SHA256(salt, secret)
  const mac1: cryptoFramework.Mac = cryptoFramework.createMac('SHA256');
  const keyGen1: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('HMAC');
  const saltKey: cryptoFramework.SymKey = await keyGen1.convertKey({ data: salt } as cryptoFramework.DataBlob);
  await mac1.init(saltKey);
  await mac1.update({ data: secret } as cryptoFramework.DataBlob);
  const prkBlob: cryptoFramework.DataBlob = await new Promise<cryptoFramework.DataBlob>(
    (resolve: (value: cryptoFramework.DataBlob) => void, reject: (reason: Error) => void): void => {
      mac1.doFinal((err: BusinessError, data: cryptoFramework.DataBlob): void => {
        if (err !== null) { reject(err as Error); return; }
        resolve(data);
      });
    }
  );
  const prk: Uint8Array = new Uint8Array(prkBlob.data);

  // Step 2: T1 = HMAC-SHA256(PRK, info || 0x01)
  const mac2: cryptoFramework.Mac = cryptoFramework.createMac('SHA256');
  const keyGen2: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('HMAC');
  const prkKey: cryptoFramework.SymKey = await keyGen2.convertKey({ data: prk } as cryptoFramework.DataBlob);
  await mac2.init(prkKey);
  const infoBytes: Uint8Array = stringToUint8Array(info);
  const infoConcat: Uint8Array = new Uint8Array(infoBytes.length + 1);
  infoConcat.set(infoBytes, 0);
  infoConcat[infoBytes.length] = 0x01;
  await mac2.update({ data: infoConcat } as cryptoFramework.DataBlob);
  const t1Blob: cryptoFramework.DataBlob = await new Promise<cryptoFramework.DataBlob>(
    (resolve: (value: cryptoFramework.DataBlob) => void, reject: (reason: Error) => void): void => {
      mac2.doFinal((err: BusinessError, data: cryptoFramework.DataBlob): void => {
        if (err !== null) { reject(err as Error); return; }
        resolve(data);
      });
    }
  );
  const t1: Uint8Array = new Uint8Array(t1Blob.data);

  return t1.subarray(0, 32);
}

/** AES-256-GCM 加密（异步，使用 cryptoFramework） */
export async function encryptAesGcm(
  plaintext: Uint8Array,
  key: Uint8Array,
  iv: Uint8Array,
): Promise<EncryptResult> {
  const symKeyGenerator: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
  const keyData: cryptoFramework.DataBlob = { data: key };
  const symKey: cryptoFramework.SymKey = await symKeyGenerator.convertKey(keyData);
  const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES256|GCM|PKCS7');
  const ivData: cryptoFramework.DataBlob = { data: iv };
  const emptyData: cryptoFramework.DataBlob = { data: new Uint8Array(0) };
  const authTagData: cryptoFramework.DataBlob = { data: new Uint8Array(16) };
  const params: cryptoFramework.GcmParamsSpec = {
    iv: ivData,
    aad: emptyData,
    authTag: authTagData,
    algName: 'GCM'
  };
  await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, params);
  const plainData: cryptoFramework.DataBlob = { data: plaintext };
  const result: cryptoFramework.DataBlob = await cipher.doFinal(plainData);
  const combined: Uint8Array = new Uint8Array(result.data);
  const tagLen: number = 16;
  const ciphertext: Uint8Array = combined.subarray(0, combined.length - tagLen);
  const tag: Uint8Array = combined.subarray(combined.length - tagLen);
  const encResult: EncryptResult = { ciphertext: ciphertext, iv: iv, tag: tag };
  return encResult;
}

/** AES-256-GCM 解密（异步，使用 cryptoFramework） */
export async function decryptAesGcm(
  ciphertext: Uint8Array,
  key: Uint8Array,
  iv: Uint8Array,
  tag: Uint8Array,
): Promise<Uint8Array> {
  const symKeyGenerator: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
  const keyData: cryptoFramework.DataBlob = { data: key };
  const symKey: cryptoFramework.SymKey = await symKeyGenerator.convertKey(keyData);
  const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES256|GCM|PKCS7');
  const combined: Uint8Array = new Uint8Array(ciphertext.length + tag.length);
  combined.set(ciphertext, 0);
  combined.set(tag, ciphertext.length);
  const ivData: cryptoFramework.DataBlob = { data: iv };
  const emptyData: cryptoFramework.DataBlob = { data: new Uint8Array(0) };
  const authTagData: cryptoFramework.DataBlob = { data: new Uint8Array(16) };
  const params: cryptoFramework.GcmParamsSpec = {
    iv: ivData,
    aad: emptyData,
    authTag: authTagData,
    algName: 'GCM'
  };
  await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, params);
  const combinedData: cryptoFramework.DataBlob = { data: combined };
  const result: cryptoFramework.DataBlob = await cipher.doFinal(combinedData);
  return new Uint8Array(result.data);
}

// ── Private helpers: key conversion wrappers ───────────────────────
// ArkTS strict mode: AsyKeyGenerator.convertKey has overloads:
//   (1) convertKey(pubKey: DataBlob, priKey: DataBlob): Promise<KeyPair>
//   (2) convertKey(pubKey: DataBlob, priKey: DataBlob, callback: AsyncCallback<KeyPair>): void
// No single-arg overload exists — both pub and priv keys must be provided.
// For pub-key-only import, pass an empty DataBlob as the private key.

function keyPairFromPubKey(
  generator: cryptoFramework.AsyKeyGenerator,
  pubKey: cryptoFramework.DataBlob
): Promise<cryptoFramework.KeyPair> {
  const emptyKey: cryptoFramework.DataBlob = { data: new Uint8Array(0) };
  return generator.convertKey(pubKey, emptyKey);
}

function keyPairFromPubAndPriv(
  generator: cryptoFramework.AsyKeyGenerator,
  pubKey: cryptoFramework.DataBlob,
  priKey: cryptoFramework.DataBlob
): Promise<cryptoFramework.KeyPair> {
  return generator.convertKey(pubKey, priKey);
}

// ── Private: Software Ed25519 ──────────────────────────────────────

async function generateSoftwareKey(): Promise<SoftwareKeyPair> {
  if (_swKeyPair !== null) return _swKeyPair;

  const generator: cryptoFramework.AsyKeyGenerator = cryptoFramework.createAsyKeyGenerator('Ed25519');
  const keyPair: cryptoFramework.KeyPair = await generator.generateKeyPair();
  const pubKeyBlob: cryptoFramework.DataBlob = await keyPair.pubKey.getEncoded();
  const privKeyBlob: cryptoFramework.DataBlob = await keyPair.priKey.getEncoded();

  const pubHex: string = bytesToHex(new Uint8Array(pubKeyBlob.data));
  const privHex: string = bytesToHex(new Uint8Array(privKeyBlob.data));

  const sw: SoftwareKeyPair = { publicKeyHex: pubHex, privateKeyHex: privHex };
  _swKeyPair = sw;
  return _swKeyPair;
}

async function signSoftware(data: string): Promise<string> {
  const sw: SoftwareKeyPair = await generateSoftwareKey();
  const pubBlob: cryptoFramework.DataBlob = { data: hexToBytes(sw.publicKeyHex) };
  const privBlob: cryptoFramework.DataBlob = { data: hexToBytes(sw.privateKeyHex) };
  const generator: cryptoFramework.AsyKeyGenerator = cryptoFramework.createAsyKeyGenerator('Ed25519');
  const keyPair: cryptoFramework.KeyPair = await keyPairFromPubAndPriv(generator, pubBlob, privBlob);

  const signer: cryptoFramework.Sign = cryptoFramework.createSign(keyPair.priKey.algName);
  await signer.init(keyPair.priKey);
  const inputData: cryptoFramework.DataBlob = { data: stringToUint8Array(data) };
  const sig: cryptoFramework.DataBlob = await signer.sign(inputData);
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
  const len: number = hex.length / 2;
  const bytes: Uint8Array = new Uint8Array(len);
  for (let i: number = 0; i < len; i++) {
    bytes[i] = parseInt(hex.substr(i * 2, 2), 16);
  }
  return bytes;
}

function stringToUint8Array(str: string): Uint8Array {
  let encoder: util.TextEncoder = new util.TextEncoder();
  return encoder.encodeInto(str);
}
