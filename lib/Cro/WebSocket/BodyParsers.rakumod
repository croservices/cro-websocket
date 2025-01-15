use Cro::BodyParser;
use JSON::Fast;

class Cro::WebSocket::BodyParser::Text does Cro::BodyParser {
    method is-applicable($message) {
        $message.is-text
    }

    method parse($message) {
        $message.body-text
    }
}

class Cro::WebSocket::BodyParser::Binary does Cro::BodyParser {
    method is-applicable($message) {
        True
    }

    method parse($message) {
        $message.body-blob
    }
}

class Cro::WebSocket::BodyParser::JSON does Cro::BodyParser {
    method is-applicable($message) {
        # We presume that if this body parser has been installed, then we will
        # always be doing JSON
        True
    }

    method parse($message) {
        $message.body-blob.then: -> $blob-promise {
            from-json $blob-promise.result.decode('utf-8')
        }
    }
}
