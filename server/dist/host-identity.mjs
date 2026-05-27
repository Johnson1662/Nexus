import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
const IDENTITY_PATH = path.resolve(process.cwd(), '.anywhere-host.json');
function generateHostId() {
    return crypto.randomUUID();
}
function generateKeyPair() {
    const x25519 = crypto.generateKeyPairSync('x25519', {
        publicKeyEncoding: { type: 'spki', format: 'jwk' },
        privateKeyEncoding: { type: 'pkcs8', format: 'jwk' },
    });
    const xPubJwk = x25519.publicKey;
    const xPrivJwk = x25519.privateKey;
    const ed25519 = crypto.generateKeyPairSync('ed25519', {
        publicKeyEncoding: { type: 'spki', format: 'jwk' },
        privateKeyEncoding: { type: 'pkcs8', format: 'jwk' },
    });
    const ePubJwk = ed25519.publicKey;
    const ePrivJwk = ed25519.privateKey;
    return {
        publicKey: Buffer.from(xPubJwk.x, 'base64url').toString('hex'),
        privateKey: Buffer.from(xPrivJwk.d, 'base64url').toString('hex'),
        ed25519PublicKey: Buffer.from(ePubJwk.x, 'base64url').toString('hex'),
        ed25519PrivateKey: Buffer.from(ePrivJwk.d, 'base64url').toString('hex'),
    };
}
export function getOrCreateHostIdentity() {
    // Phase 2b: Key rotation via ANYWHERE_ROTATE_KEYS=1
    if (process.env.ANYWHERE_ROTATE_KEYS === '1') {
        try {
            fs.unlinkSync(IDENTITY_PATH);
            console.log('[host-identity] Key rotation: deleted existing identity file');
        }
        catch { }
    }
    let schemaVersion = 1;
    let hostId;
    let publicKeyHex;
    let privateKeyHex;
    let ed25519PublicKeyHex;
    let ed25519PrivateKeyHex;
    try {
        const raw = fs.readFileSync(IDENTITY_PATH, 'utf-8');
        const data = JSON.parse(raw);
        schemaVersion = typeof data.schemaVersion === 'number' ? data.schemaVersion : 0;
        if (typeof data.hostId === 'string' && data.hostId.length > 0) {
            hostId = data.hostId;
            publicKeyHex = data.publicKeyHex;
            privateKeyHex = data.privateKeyHex;
            ed25519PublicKeyHex = data.ed25519PublicKeyHex;
            ed25519PrivateKeyHex = data.ed25519PrivateKeyHex;
        }
        else {
            hostId = generateHostId();
        }
    }
    catch {
        hostId = generateHostId();
    }
    // Re-generate keys if missing (but preserve hostId)
    if (!publicKeyHex || !privateKeyHex || !ed25519PublicKeyHex || !ed25519PrivateKeyHex) {
        const keys = generateKeyPair();
        publicKeyHex ??= keys.publicKey;
        privateKeyHex ??= keys.privateKey;
        ed25519PublicKeyHex ??= keys.ed25519PublicKey;
        ed25519PrivateKeyHex ??= keys.ed25519PrivateKey;
    }
    schemaVersion = 1;
    const data = {
        schemaVersion,
        hostId,
        publicKeyHex,
        privateKeyHex,
        ed25519PublicKeyHex,
        ed25519PrivateKeyHex,
    };
    fs.writeFileSync(IDENTITY_PATH, JSON.stringify(data, null, 2), 'utf-8');
    return data;
}
export function getOrCreateHostId() {
    return getOrCreateHostIdentity().hostId;
}
//# sourceMappingURL=host-identity.mjs.map