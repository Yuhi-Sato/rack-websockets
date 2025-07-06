// @ts-nocheck
import net from 'node:net';
import crypto from 'node:crypto';

/**
 * Minimal WebSocket client that implements only the parts
 * required for text messaging with the echo server.
 */
export class SimpleWebSocketClient {
  private socket: net.Socket;
  private buffer: Buffer = Buffer.alloc(0);
  private readonly host: string;
  private readonly port: number;
  private readonly path: string;

  constructor(host: string = 'localhost', port: number = 3000, path: string = '/') {
    this.host = host;
    this.port = port;
    this.path = path;
    this.socket = new net.Socket();
  }

  /** Connect to the WebSocket server and perform handshake */
  async connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.socket.connect(this.port, this.host, () => {
        const key = crypto.randomBytes(16).toString('base64');
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
      const onData = (chunk: Buffer) => {
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
  send(message: string): void {
    const opcode = 0x1; // text frame
    const payload = Buffer.from(message, 'utf8');
    const maskKey = crypto.randomBytes(4);
    const masked = Buffer.alloc(payload.length);
    for (let i = 0; i < payload.length; i++) {
      masked[i] = payload[i] ^ maskKey[i % 4];
    }

    const parts: number[] = [];
    parts.push(0b1000_0000 | opcode); // FIN + opcode
    const len = masked.length;
    if (len < 126) {
      parts.push(0b1000_0000 | len); // mask bit set
    } else if (len < 65536) {
      parts.push(0b1000_0000 | 126);
    } else {
      parts.push(0b1000_0000 | 127);
    }
    const header = Buffer.from(parts);
    let extraLength: Buffer = Buffer.alloc(0);
    if (len >= 126 && len < 65536) {
      extraLength = Buffer.alloc(2);
      extraLength.writeUInt16BE(len, 0);
    } else if (len >= 65536) {
      extraLength = Buffer.alloc(8);
      extraLength.writeBigUInt64BE(BigInt(len), 0);
    }
    this.socket.write(Buffer.concat([header, extraLength, maskKey, masked]));
  }

  /** Start listening for text frames */
  onMessage(callback: (msg: string) => void): void {
    this.socket.on('data', (chunk) => {
      this.buffer = Buffer.concat([this.buffer, chunk]);
      while (true) {
        if (this.buffer.length < 2) return;
        const byte1 = this.buffer[0];
        const byte2 = this.buffer[1];
        const opcode = byte1 & 0b0000_1111;
        let offset = 2;
        let len = byte2 & 0b0111_1111;
        if (len === 126) {
          if (this.buffer.length < offset + 2) return;
          len = this.buffer.readUInt16BE(offset);
          offset += 2;
        } else if (len === 127) {
          if (this.buffer.length < offset + 8) return;
          const bigLen = this.buffer.readBigUInt64BE(offset);
          len = Number(bigLen);
          offset += 8;
        }
        const masked = byte2 & 0b1000_0000;
        let mask: Buffer = Buffer.alloc(0);
        if (masked) {
          if (this.buffer.length < offset + 4) return;
          mask = this.buffer.slice(offset, offset + 4);
          offset += 4;
        }
        if (this.buffer.length < offset + len) return;
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
        } else if (opcode === 0x8) {
          this.socket.end();
          return;
        }
      }
    });
  }
}

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
