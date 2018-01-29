use Cro::MessageWithBody;

class Cro::WebSocket::Message does Cro::MessageWithBody {
    enum Opcode (:Text(1), :Binary(2), :Ping(9), :Pong(10), :Close(8));
    has Opcode $.opcode;

    has Bool $.fragmented;

    has Supply $.body-byte-stream;

    multi method new(Str $body) {
        self.bless: opcode => Text, fragmented => False, body-byte-stream => supply {
            emit $body.encode('utf-8');
        }
    }
    multi method new(Blob $body) {
        self.bless: opcode => Binary, fragmented => False, body-byte-stream => supply {
            emit $body;
        }
    }
    multi method new(Supply $supply) {
        self.bless: opcode => Binary, fragmented => True, body-byte-stream => $supply;
    }

    method is-text() { $!opcode == Text }
    method is-binary() { $!opcode == Binary }
    method is-data() { $!opcode == Text | Binary }

    method body-text-encoding(Blob $blob) { self.is-text ?? 'utf-8' !! Nil }

    method trace-output(--> Str) {
        "WebSocket Message - {$!opcode}\n";
    }
}
