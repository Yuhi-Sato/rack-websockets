# rack-websockets

This repository includes a minimal Rack style server that implements WebSocket
support using only Ruby's standard library. Run the server with:

```
ruby websocket_rack_server.rb
```

Then connect with a WebSocket client to `ws://localhost:3000` and the server
will echo text messages.

