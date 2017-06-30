use Cro::Message;

class Cro::WebSocket::Frame does Cro::Message {
    enum Opcode (:Continuation(0),
                 :Text(1), :Binary(2),
                 :Close(8), :Ping(9), :Pong(10));

    has Bool $.fin is rw;
    has Opcode $.opcode is rw;
    has Blob $.payload is rw;
}
