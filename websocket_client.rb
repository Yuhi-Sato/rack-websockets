#!/usr/bin/env ruby
require 'socket'
require 'digest/sha1'
require 'base64'

class WebSocketClient
  MAGIC = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'

  def initialize(host: 'localhost', port: 3000, path: '/')
    @host = host
    @port = port
    @path = path
  end

  def run
    TCPSocket.open(@host, @port) do |sock|
      key = Base64.strict_encode64(Random.new.bytes(16))
      request = [
        "GET #{@path} HTTP/1.1",
        "Host: #{@host}:#{@port}",
        'Upgrade: websocket',
        'Connection: Upgrade',
        "Sec-WebSocket-Key: #{key}",
        'Sec-WebSocket-Version: 13',
        '',
        ''
      ].join("\r\n")
      sock.write(request)
      while (line = sock.gets)
        break if line == "\r\n"
      end
      send_frame(sock, 'hello from client')
      opcode, payload = read_frame(sock)
      puts "Received: #{payload}" if opcode == 0x1
      send_close(sock)
    end
  end

  private

  def send_frame(sock, payload, opcode = 0x1)
    frame = [0b1000_0000 | opcode]
    len = payload.bytesize
    if len < 126
      frame << (0b1000_0000 | len)
    elsif len < 65_536
      frame << (0b1000_0000 | 126)
      frame.concat [len].pack('n').bytes
    else
      frame << (0b1000_0000 | 127)
      frame.concat [len].pack('Q>').bytes
    end
    mask = Random.new.bytes(4).bytes
    frame.concat mask
    data = payload.bytes.map.with_index { |b, i| b ^ mask[i % 4] }
    sock.write(frame.pack('C*') + data.pack('C*'))
  end

  def read_frame(sock)
    header = sock.read(2)
    return unless header
    byte1, byte2 = header.bytes
    opcode = byte1 & 0b0000_1111
    len = byte2 & 0b0111_1111
    len = sock.read(2).unpack1('n') if len == 126
    len = sock.read(8).unpack1('Q>') if len == 127
    data = sock.read(len)
    [opcode, data]
  end

  def send_close(sock)
    sock.write([0b1000_1000, 0].pack('CC'))
  end
end

if __FILE__ == $0
  host = ENV.fetch('HOST', 'localhost')
  port = ENV.fetch('PORT', '3000').to_i
  client = WebSocketClient.new(host: host, port: port)
  client.run
end
