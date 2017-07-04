use Cro::Message;

class Cro::WebSocket::Message does Cro::Message {
    enum Opcode <Text Binary Ping Pong Close>;
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

    # Gets the body as text, asynchronously (decoding it as UTF-8)
    method body-text(--> Promise) {
        my $p = Promise.new;
        $!body-byte-stream.tap(-> $body { $p.keep($body.decode('utf-8')) });
        $p;
    }

    # Gets the body as a Blob, asynchronously
    method body-blob(--> Promise) {
        my $p = Promise.new;
        $!body-byte-stream.tap(-> $body { $p.keep($body) });
        $p;
    }
}
