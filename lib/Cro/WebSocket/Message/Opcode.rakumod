package Cro::WebSocket::Message {
    enum Opcode is export (:Text(1), :Binary(2), :Ping(9), :Pong(10), :Close(8));
}
