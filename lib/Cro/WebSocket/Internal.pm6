use Cro::BodyParserSelector;
use Cro::BodySerializerSelector;
use Cro::Transform;
use Cro::WebSocket::Message;

my class SetBodyParsers does Cro::Transform is export {
    has $!selector;

    method BUILD(:$body-parsers --> Nil) {
        $!selector = Cro::BodyParserSelector::List.new:
            parsers => $body-parsers.list;
    }

    method consumes() { Cro::WebSocket::Message }
    method produces() { Cro::WebSocket::Message }

    method transformer(Supply $in --> Supply) {
        supply whenever $in {
            .body-parser-selector = $!selector;
            .emit;
        }
    }
}

my class SetBodySerializers does Cro::Transform is export {
    has $!selector;

    method BUILD(:$body-serializers --> Nil) {
        $!selector = Cro::BodySerializerSelector::List.new:
            serializers => $body-serializers.list;
    }

    method consumes() { Cro::WebSocket::Message }
    method produces() { Cro::WebSocket::Message }

    method transformer(Supply $in --> Supply) {
        supply whenever $in {
            .body-serializer-selector = $!selector;
            .emit;
        }
    }
}
