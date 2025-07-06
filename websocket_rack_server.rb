#!/usr/bin/env ruby
require 'socket'
require 'digest/sha1'
require 'base64'
require 'stringio'

class WebSocketApp
  MAGIC = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'

  def call(env)
    sock = env['websocket.socket']
    if env['HTTP_UPGRADE'].to_s.downcase == 'websocket'
      key = env['HTTP_SEC_WEBSOCKET_KEY']
      accept = Base64.strict_encode64(Digest::SHA1.digest(key + MAGIC))
      sock.write "HTTP/1.1 101 Switching Protocols\r\n"
      sock.write "Upgrade: websocket\r\n"
      sock.write "Connection: Upgrade\r\n"
      sock.write "Sec-WebSocket-Accept: #{accept}\r\n"
      sock.write "\r\n"
      handle_websocket(sock)
      return [nil, {}, []]
    else
      body = "Use a WebSocket client to connect\n"
      return [200,
              {'Content-Type' => 'text/plain', 'Content-Length' => body.bytesize.to_s},
              [body]]
    end
  end

  def handle_websocket(sock)
    loop do
      header = sock.read(2)
      break unless header
      byte1, byte2 = header.bytes
      opcode = byte1 & 0b0000_1111
      masked = byte2 & 0b1000_0000 != 0
      len = byte2 & 0b0111_1111
      len = sock.read(2).unpack1('n') if len == 126
      len = sock.read(8).unpack1('Q>') if len == 127
      mask = masked ? sock.read(4).bytes : []
      data = sock.read(len).bytes
      data.map!.with_index { |b, i| b ^ mask[i % 4] } if masked
      case opcode
      when 0x8
        send_frame(sock, '', 0x8)
        sock.close
        break
      when 0x1
        msg = data.pack('C*')
        send_frame(sock, "echo: #{msg}", 0x1)
      end
    end
  end

  def send_frame(sock, payload, opcode)
    frame = [0b1000_0000 | opcode]
    len = payload.bytesize
    if len < 126
      frame << len
    elsif len < 65_536
      frame << 126
      frame.concat [len].pack('n').bytes
    else
      frame << 127
      frame.concat [len].pack('Q>').bytes
    end
    sock.write frame.pack('C*') + payload
  end
end

class SimpleRackServer
  def initialize(app, port: 3000)
    @app = app
    @server = TCPServer.new(port)
    puts "Listening on port #{port}"
  end

  def start
    loop do
      sock = @server.accept
      Thread.new(sock) { |client| handle(client) }
    end
  end

  def handle(client)
    request_line = client.gets
    return unless request_line
    method, fullpath, _ = request_line.split
    path, query = fullpath.split('?', 2)
    headers = {}
    while (line = client.gets)
      break if line == "\r\n"
      name, value = line.split(': ', 2)
      headers[name] = value.strip
    end
    env = {
      'REQUEST_METHOD' => method,
      'PATH_INFO' => path,
      'QUERY_STRING' => query.to_s,
      'rack.input' => StringIO.new,
      'websocket.socket' => client
    }
    headers.each { |k, v| env['HTTP_' + k.upcase.tr('-', '_')] = v }
    status, h, body = @app.call(env)
    if status
      client.write "HTTP/1.1 #{status} OK\r\n"
      h.each { |k, v| client.write "#{k}: #{v}\r\n" }
      client.write "\r\n"
      body.each { |part| client.write part }
      client.close
    end
  rescue => e
    warn e
    client.close rescue nil
  end
end

if __FILE__ == $0
  port = ENV.fetch('PORT', '3000').to_i
  server = SimpleRackServer.new(WebSocketApp.new, port: port)
  server.start
end
