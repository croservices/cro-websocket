use Cro::BodyParserSelector;
use Cro::BodySerializerSelector;
use Cro::MessageWithBody;
use Cro::WebSocket::BodyParsers;
use Cro::WebSocket::BodySerializers;
use Cro::WebSocket::Message::Opcode;

class Cro::WebSocket::Message does Cro::MessageWithBody {
    has Cro::WebSocket::Message::Opcode $.opcode is rw;
    has Bool $.fragmented;
    has Cro::BodyParserSelector $.body-parser-selector is rw =
        Cro::BodyParserSelector::List.new:
            :parsers[
                Cro::WebSocket::BodyParser::Text,
                Cro::WebSocket::BodyParser::Binary
            ];
    has Cro::BodySerializerSelector $.body-serializer-selector is rw =
        Cro::BodySerializerSelector::List.new:
            :serializers[
                Cro::WebSocket::BodySerializer::Text,
                Cro::WebSocket::BodySerializer::Binary
            ];

    multi method new(Supply $body-byte-stream) {
        self.bless: :opcode(Binary), :fragmented, :$body-byte-stream;
    }
    multi method new($body) {
        self.bless:
            :opcode($body ~~ Str ?? Text !! Binary),
            :fragmented($body !~~ Str && $body !~~ Blob),
            :$body;
    }

    submethod TWEAK(:$body-byte-stream, :$body) {
        with $body-byte-stream {
            self.set-body-byte-stream($body-byte-stream);
        }
        orwith $body {
            self.set-body($body);
        }
    }

    method is-text() { $!opcode == Text }
    method is-binary() { $!opcode == Binary }
    method is-data() { $!opcode == Text | Binary }

    method body-text-encoding(Blob $blob) { self.is-text ?? 'utf-8' !! Nil }

    method trace-output(--> Str) {
        "WebSocket Message - {$!opcode // 'Opcode Unset'}\n";
    }
}
