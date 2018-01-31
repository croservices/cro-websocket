use Cro::Transform;
use Cro::WebSocket::Frame;
use Cro::WebSocket::Message;
use Cro::WebSocket::Message::Opcode;

class Cro::WebSocket::MessageParser does Cro::Transform {
    method consumes() { Cro::WebSocket::Frame }
    method produces() { Cro::WebSocket::Message }

    method transformer(Supply:D $in) {
        supply {
            my $last;
            whenever $in -> Cro::WebSocket::Frame $frame {
                # Control frames are processed immediately
                if $frame.opcode.value == 8|9|10 {
                    emit Cro::WebSocket::Message.new(opcode => Cro::WebSocket::Message::Opcode($frame.opcode.value),
                                                     fragmented => False,
                                                     body-byte-stream => supply emit $frame.payload);
                } else {
                    if $frame.fin {
                        if $frame.opcode == 0 {
                            $last.emit($frame.payload);
                            $last.done;
                            $last = Supplier::Preserving.new;
                        } else {
                            emit Cro::WebSocket::Message.new(
                                opcode => Cro::WebSocket::Message::Opcode($frame.opcode.value),
                                fragmented => False,
                                body-byte-stream => supply emit $frame.payload);
                        }
                    } else {
                        if $frame.opcode == 0 {
                            $last.emit($frame.payload);
                        } else {
                            $last = Supplier::Preserving.new;
                            $last.emit($frame.payload);
                            emit Cro::WebSocket::Message.new(
                                opcode => Cro::WebSocket::Message::Opcode($frame.opcode.value),
                                fragmented => True,
                                body-byte-stream => $last.Supply);
                        }
                    }
                }
            }
        }
    }
}
