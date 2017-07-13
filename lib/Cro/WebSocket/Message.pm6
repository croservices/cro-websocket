use Cro::Message;

class Cro::WebSocket::Message does Cro::Message {
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

    method body-text(--> Promise) {
        self.body-blob.then: -> $p { $p.result.decode('utf-8') }
    }

    method body-blob(--> Promise) {
        Promise(supply {
                       my $joined = Blob.new;
                       whenever $!body-byte-stream -> Blob $blob {
                           $joined = $joined ~ $blob if $blob;
                           LAST emit $joined;
                       }
                   })
    }
}
