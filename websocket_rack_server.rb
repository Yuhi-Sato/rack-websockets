#!/usr/bin/env ruby
# Ruby 標準ライブラリのみを使った WebSocket 対応の
# シンプルな Rack 風サーバーのサンプルです。

# ソケット通信を行うためのライブラリ
require 'socket'
# WebSocket ハンドシェイクで利用する SHA1 ハッシュ計算用
require 'digest/sha1'
# ハンドシェイクの応答値を Base64 でエンコードするために使用
require 'base64'

class WebSocketApp
  # WebSocket ハンドシェイクで利用する固定値
  MAGIC = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'

  # Rack アプリのインターフェイス
  # 簡易的な env ハッシュから WebSocket かどうかを判定し
  # WebSocket 接続であればハンドシェイクを行います
  def call(env)
    # ソケットオブジェクトは env に格納されています
    sock = env['websocket.socket']

    # HTTP ヘッダーから Upgrade: websocket が送られてきたか確認
    if env['HTTP_UPGRADE'].to_s.downcase == 'websocket'
      # クライアントから送られたキーを使って応答用の値を生成
      key = env['HTTP_SEC_WEBSOCKET_KEY']
      accept = Base64.strict_encode64(Digest::SHA1.digest(key + MAGIC))

      # WebSocket 仕様に沿ってハンドシェイク成功を伝える HTTP 応答を返す
      sock.write "HTTP/1.1 101 Switching Protocols\r\n"
      sock.write "Upgrade: websocket\r\n"
      sock.write "Connection: Upgrade\r\n"
      sock.write "Sec-WebSocket-Accept: #{accept}\r\n"
      sock.write "\r\n"

      # ハンドシェイクが完了したので WebSocket のメッセージ処理へ
      handle_websocket(sock)

      # Rack としてはレスポンスを返さないため nil を返却
      return [nil, {}, []]
    else
      # ブラウザなど HTTP リクエストでアクセスされた場合の通常応答
      body = "Use a WebSocket client to connect\n"
      return [200,
              {'Content-Type' => 'text/plain', 'Content-Length' => body.bytesize.to_s},
              [body]]
    end
  end

  # WebSocket フレームを読み取り、簡単なエコー処理を行う
  def handle_websocket(sock)
    loop do
      # まず 2 バイトのヘッダを取得
      header = sock.read(2)
      # 接続が切れたらループ終了
      break unless header

      byte1, byte2 = header.bytes
      # opcode にはメッセージの種類が入る
      opcode = byte1 & 0b0000_1111
      # マスクされているかどうか
      masked = byte2 & 0b1000_0000 != 0
      # ペイロード長を取得
      len = byte2 & 0b0111_1111
      len = sock.read(2).unpack1('n') if len == 126
      len = sock.read(8).unpack1('Q>') if len == 127

      # マスクキーを取得 (クライアントからのデータは必ずマスクされている)
      mask = masked ? sock.read(4).bytes : []
      data = sock.read(len).bytes

      # マスクされていれば実データを復号
      data.map!.with_index { |b, i| b ^ mask[i % 4] } if masked

      case opcode
      when 0x8 # close フレーム
        send_frame(sock, '', 0x8)
        sock.close
        break
      when 0x1 # テキストメッセージ
        msg = data.pack('C*')
        # 受け取ったメッセージをそのまま echo
        send_frame(sock, "echo: #{msg}", 0x1)
      end
    end
  end

  # サーバーからクライアントへ WebSocket フレームを送信する
  def send_frame(sock, payload, opcode)
    # 先頭バイト: FIN フラグと opcode
    frame = [0b1000_0000 | opcode]
    len = payload.bytesize

    # ペイロード長に応じてフォーマットを変える
    if len < 126
      frame << len
    elsif len < 65_536
      frame << 126
      frame.concat [len].pack('n').bytes
    else
      frame << 127
      frame.concat [len].pack('Q>').bytes
    end

    # バイナリ列としてソケットに書き込む
    sock.write frame.pack('C*') + payload
  end
end

class SimpleRackServer
  # Rack アプリケーションを受け取り TCPServer を起動するだけの簡易サーバー
  def initialize(app, port: 3000)
    @app = app
    # 指定ポートで待ち受ける
    @server = TCPServer.new(port)
    puts "Listening on port #{port}"
  end

  # 接続を待ち受け、来たらスレッドを作って処理する
  def start
    loop do
      sock = @server.accept
      Thread.new(sock) { |client| handle(client) }
    end
  end

  # 1 つの接続に対する処理。HTTP リクエストを読み取り Rack 形式に変換する
  def handle(client)
    request_line = client.gets
    return unless request_line

    # 今回は WebSocket 接続のみを想定しているため
    # リクエストラインの内容は特に利用しません
    _method, _fullpath, _ = request_line.split
    headers = {}

    # 空行まで HTTP ヘッダーを読み込む
    while (line = client.gets)
      break if line == "\r\n"
      name, value = line.split(': ', 2)
      headers[name] = value.strip
    end

    # Rack で使う環境変数を最低限だけ組み立てる
    env = { 'websocket.socket' => client }
    headers.each { |k, v| env['HTTP_' + k.upcase.tr('-', '_')] = v }

    # Rack アプリに処理を委譲
    status, h, body = @app.call(env)

    # status が nil でなければ通常の HTTP 応答として返す
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
  # ポート番号は固定で 3000 番を使用
  server = SimpleRackServer.new(WebSocketApp.new)
  server.start
end
