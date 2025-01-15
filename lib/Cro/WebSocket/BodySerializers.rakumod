use Cro::BodySerializer;
use Cro::WebSocket::Message::Opcode;
use JSON::Fast;

class Cro::WebSocket::BodySerializer::Text does Cro::BodySerializer {
    method is-applicable($message, $body) {
        $body ~~ Str
    }

    method serialize($message, $body) {
        $message.opcode = Text;
        supply emit $body.encode('utf-8')
    }
}

class Cro::WebSocket::BodySerializer::Binary does Cro::BodySerializer {
    method is-applicable($message, $body) {
        $body ~~ Blob
    }

    method serialize($message, $blob) {
        $message.opcode = Binary;
        supply emit $blob
    }
}

class Cro::WebSocket::BodySerializer::JSON does Cro::BodySerializer {
    method is-applicable($message, $body) {
        # We presume that if this body serializer has been installed, then we
        # will always be doing JSON
        True
    }

    method serialize($message, $body) {
        $message.opcode = Text;
        supply emit to-json($body).encode('utf-8')
    }
}
