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
                my $opcode = $frame.opcode;
                if $frame.fin {
                    # Single frame message
                    if $opcode {
                        emit Cro::WebSocket::Message.new:
                            opcode => Cro::WebSocket::Message::Opcode($opcode.value),
                            :!fragmented, body-byte-stream => supply emit $frame.payload;
                    }
                    # Final frame of a fragmented message
                    else {
                        $last.emit($frame.payload);
                        $last.done;
                    }
                }
                else {
                    # First frame of a fragmented message
                    if $opcode {
                        $last = Supplier::Preserving.new;
                        $last.emit($frame.payload);
                        emit Cro::WebSocket::Message.new:
                            opcode => Cro::WebSocket::Message::Opcode($opcode.value),
                            :fragmented, body-byte-stream => $last.Supply;
                    }
                    # Continuation frame
                    else {
                        $last.emit($frame.payload);
                    }
                }
            }
        }
    }
}
