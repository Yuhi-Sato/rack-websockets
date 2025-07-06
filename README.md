# rack-websockets

This repository includes a minimal Rack style server that implements WebSocket support using only Ruby's standard library. Run the server with:

```
ruby websocket_rack_server.rb
```

A simple WebSocket client written in TypeScript is also provided. Compile it with `tsc` and run the resulting script to connect to the server:

```
# compile
tsc
# run
node dist/simple_websocket_client.js
```

After connecting to `ws://localhost:3000` the client sends a `hello` message and prints the echoed response.
