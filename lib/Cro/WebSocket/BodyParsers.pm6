use Cro::BodyParser;

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
