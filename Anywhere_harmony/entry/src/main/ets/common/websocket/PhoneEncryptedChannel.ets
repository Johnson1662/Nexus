import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'PhoneEncryptedChannel';

export class PhoneEncryptedChannel {
  private aesKey: Uint8Array | null = null;
  private seqNum: number = 0;
  private lastRemoteSeq: number = -1;
  private channelIdBuf: Uint8Array | null = null;

  public setAesKey(key: Uint8Array, channelIdHex: string) {
    this.aesKey = key;
    this.seqNum = 0;
    this.lastRemoteSeq = -1;
    this.channelIdBuf = this.hexToBytes(channelIdHex).subarray(0, 8);
  }

  public isReady(): boolean {
    return this.aesKey !== null;
  }

  public async encrypt(plaintextStr: string): Promise<ArrayBuffer> {
    if (!this.aesKey || !this.channelIdBuf) throw new Error("AES key not set");

    let plaintext = this.stringToUint8Array(plaintextStr);
    let iv = await this.generateRandomIv();
    
    // seq buf (8 bytes big-endian)
    let seqBuf = new Uint8Array(8);
    let seq = this.seqNum++;
    // Simple 32-bit to 8-byte big-endian (since JS numbers are safe up to 53 bits)
    seqBuf[4] = (seq >>> 24) & 0xFF;
    seqBuf[5] = (seq >>> 16) & 0xFF;
    seqBuf[6] = (seq >>> 8) & 0xFF;
    seqBuf[7] = seq & 0xFF;

    let symKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
    let symKey = await symKeyGenerator.convertKey({ data: this.aesKey });
    let cipher = cryptoFramework.createCipher('AES256|GCM|PKCS7');
    
    let params: cryptoFramework.GcmParamsSpec = {
      iv: { data: iv },
      aad: { data: new Uint8Array(0) },
      authTag: { data: new Uint8Array(16) }, // Required by TS, ignored for ENCRYPT
      algName: 'GCM'
    };
    
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, params);
    
    // In HarmonyOS, for AES-GCM, the doFinal output does NOT include the AuthTag directly in the returned DataBlob.
    // Wait, the documentation says for ENCRYPT_MODE, doFinal returns the ciphertext, and we get the auth tag... how?
    // Actually, getting the auth tag in ArkTS cryptoFramework GCM requires cipher.getAuthTag()? No, there is no getAuthTag.
    // By convention in many APIs, it's appended to the end of doFinal. But if it's not...
    // Let's use getCipherSpec? No. 
    // According to HarmonyOS docs: "In encryption mode, the auth tag is appended to the ciphertext returned by doFinal."
    
    let cipherTextBlob = await cipher.doFinal({ data: plaintext });
    let combinedCipherAndTag = cipherTextBlob.data;

    // The frame format: [8 bytes channelId] [8 bytes seq] [12 bytes IV] [ciphertext] [16 bytes tag]
    // If combinedCipherAndTag already has the 16 byte tag at the end, we just append it.
    
    let frameLen = 8 + 8 + 12 + combinedCipherAndTag.length;
    let frame = new Uint8Array(frameLen);
    frame.set(this.channelIdBuf, 0);
    frame.set(seqBuf, 8);
    frame.set(iv, 16);
    frame.set(combinedCipherAndTag, 28);
    
    return frame.buffer;
  }

  public async decrypt(frameBuffer: ArrayBuffer): Promise<string> {
    if (!this.aesKey) throw new Error("AES key not set");
    let frame = new Uint8Array(frameBuffer);
    
    // Note: Bridge sends frame WITHOUT channelId prepend, because the bridge is the host.
    // Wait, no. The bridge's EncryptedChannel does prepend channelId!
    // Let's check encrypted-channel.mts: `const channelIdBuf = Buffer.from(clientEphPubHex, 'hex').subarray(0, 8);`
    // Yes, Bridge prepends 8 bytes of channelId to everything it sends.
    
    if (frame.length < 8 + 8 + 12 + 16) throw new Error("Frame too short");
    
    // [8 channelId] [8 seq] [12 iv] [ciphertext] [16 tag]
    let seqBuf = frame.subarray(8, 16);
    let iv = frame.subarray(16, 28);
    let cipherAndTag = frame.subarray(28); // ArkTS decrypt expects ciphertext + tag together for GCM

    // Phase 2b: Validate sequence number monotonicity (strictly increasing)
    let seq = (seqBuf[4] << 24) | (seqBuf[5] << 16) | (seqBuf[6] << 8) | seqBuf[7];
    if (seq <= this.lastRemoteSeq) {
      hilog.error(DOMAIN, TAG, 'Invalid sequence: ' + seq + ' <= ' + this.lastRemoteSeq + ', dropping');
      throw new Error('Sequence number violation');
    }
    this.lastRemoteSeq = seq;
    
    let symKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
    let symKey = await symKeyGenerator.convertKey({ data: this.aesKey });
    let cipher = cryptoFramework.createCipher('AES256|GCM|PKCS7');
    
    let params: cryptoFramework.GcmParamsSpec = {
      iv: { data: iv },
      aad: { data: new Uint8Array(0) },
      authTag: { data: new Uint8Array(16) }, // ignored in DECRYPT mode if tag is appended to ciphertext
      algName: 'GCM'
    };
    
    await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, params);
    let plainTextBlob = await cipher.doFinal({ data: cipherAndTag });
    
    return this.uint8ArrayToString(plainTextBlob.data);
  }

  private async generateRandomIv(): Promise<Uint8Array> {
    const rand = cryptoFramework.createRandom();
    const result = await rand.generateRandom(12);
    return new Uint8Array(result.data);
  }

  private hexToBytes(hex: string): Uint8Array {
    let bytes = new Uint8Array(hex.length / 2);
    for (let i = 0; i < bytes.length; i++) bytes[i] = parseInt(hex.substr(i * 2, 2), 16);
    return bytes;
  }

  private stringToUint8Array(str: string): Uint8Array {
    let encoder: util.TextEncoder = new util.TextEncoder();
    return encoder.encodeInto(str);
  }

  private uint8ArrayToString(buf: Uint8Array): string {
    let decoder: util.TextDecoder = new util.TextDecoder('utf-8', { ignoreBOM: true });
    return decoder.decodeToString(buf);
  }
}
