# rack-websockets

This repository includes a minimal Rack style server that implements WebSocket
support using only Ruby's standard library. Run the server with:

```
ruby websocket_rack_server.rb
```

A simple client using the same low level WebSocket protocol is available:

```
ruby websocket_client.rb
```

The server echoes any text message sent by the client.
