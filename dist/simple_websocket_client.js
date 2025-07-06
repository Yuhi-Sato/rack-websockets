"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.SimpleWebSocketClient = void 0;
// @ts-nocheck
const node_net_1 = __importDefault(require("node:net"));
const node_crypto_1 = __importDefault(require("node:crypto"));
/**
 * Minimal WebSocket client that implements only the parts
 * required for text messaging with the echo server.
 */
class SimpleWebSocketClient {
    constructor(host = 'localhost', port = 3000, path = '/') {
        this.buffer = Buffer.alloc(0);
        this.host = host;
        this.port = port;
        this.path = path;
        this.socket = new node_net_1.default.Socket();
    }
    /** Connect to the WebSocket server and perform handshake */
    async connect() {
        return new Promise((resolve, reject) => {
            this.socket.connect(this.port, this.host, () => {
                const key = node_crypto_1.default.randomBytes(16).toString('base64');
                const headers = [
                    `GET ${this.path} HTTP/1.1`,
                    `Host: ${this.host}:${this.port}`,
                    'Upgrade: websocket',
                    'Connection: Upgrade',
                    `Sec-WebSocket-Key: ${key}`,
                    'Sec-WebSocket-Version: 13',
                    '',
                    ''
                ].join('\r\n');
                this.socket.write(headers);
            });
            let headerBuffer = Buffer.alloc(0);
            const onData = (chunk) => {
                headerBuffer = Buffer.concat([headerBuffer, chunk]);
                const headerEnd = headerBuffer.indexOf('\r\n\r\n');
                if (headerEnd !== -1) {
                    this.socket.off('data', onData);
                    const headerStr = headerBuffer.slice(0, headerEnd).toString();
                    const lines = headerStr.split(/\r\n/);
                    const statusLine = lines.shift() || '';
                    const [, status] = statusLine.split(' ');
                    if (status !== '101') {
                        reject(new Error('Handshake failed: ' + statusLine));
                        return;
                    }
                    // Handshake complete
                    resolve();
                }
            };
            this.socket.on('data', onData);
            this.socket.on('error', (err) => {
                reject(err);
            });
        });
    }
    /** Send a text message */
    send(message) {
        const opcode = 0x1; // text frame
        const payload = Buffer.from(message, 'utf8');
        const maskKey = node_crypto_1.default.randomBytes(4);
        const masked = Buffer.alloc(payload.length);
        for (let i = 0; i < payload.length; i++) {
            masked[i] = payload[i] ^ maskKey[i % 4];
        }
        const parts = [];
        parts.push(128 | opcode); // FIN + opcode
        const len = masked.length;
        if (len < 126) {
            parts.push(128 | len); // mask bit set
        }
        else if (len < 65536) {
            parts.push(128 | 126);
        }
        else {
            parts.push(128 | 127);
        }
        const header = Buffer.from(parts);
        let extraLength = Buffer.alloc(0);
        if (len >= 126 && len < 65536) {
            extraLength = Buffer.alloc(2);
            extraLength.writeUInt16BE(len, 0);
        }
        else if (len >= 65536) {
            extraLength = Buffer.alloc(8);
            extraLength.writeBigUInt64BE(BigInt(len), 0);
        }
        this.socket.write(Buffer.concat([header, extraLength, maskKey, masked]));
    }
    /** Start listening for text frames */
    onMessage(callback) {
        this.socket.on('data', (chunk) => {
            this.buffer = Buffer.concat([this.buffer, chunk]);
            while (true) {
                if (this.buffer.length < 2)
                    return;
                const byte1 = this.buffer[0];
                const byte2 = this.buffer[1];
                const opcode = byte1 & 15;
                let offset = 2;
                let len = byte2 & 127;
                if (len === 126) {
                    if (this.buffer.length < offset + 2)
                        return;
                    len = this.buffer.readUInt16BE(offset);
                    offset += 2;
                }
                else if (len === 127) {
                    if (this.buffer.length < offset + 8)
                        return;
                    const bigLen = this.buffer.readBigUInt64BE(offset);
                    len = Number(bigLen);
                    offset += 8;
                }
                const masked = byte2 & 128;
                let mask = Buffer.alloc(0);
                if (masked) {
                    if (this.buffer.length < offset + 4)
                        return;
                    mask = this.buffer.slice(offset, offset + 4);
                    offset += 4;
                }
                if (this.buffer.length < offset + len)
                    return;
                let payload = this.buffer.slice(offset, offset + len);
                if (masked) {
                    const unmasked = Buffer.alloc(payload.length);
                    for (let i = 0; i < payload.length; i++) {
                        unmasked[i] = payload[i] ^ mask[i % 4];
                    }
                    payload = unmasked;
                }
                this.buffer = this.buffer.slice(offset + len);
                if (opcode === 0x1) {
                    callback(payload.toString('utf8'));
                }
                else if (opcode === 0x8) {
                    this.socket.end();
                    return;
                }
            }
        });
    }
}
exports.SimpleWebSocketClient = SimpleWebSocketClient;
// Example usage
if (require.main === module) {
    (async () => {
        const client = new SimpleWebSocketClient();
        await client.connect();
        client.onMessage((msg) => {
            console.log('Received:', msg);
        });
        client.send('hello');
    })().catch((e) => {
        console.error(e);
    });
}
