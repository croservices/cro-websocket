use Cro::Transform;
use Cro::WebSocket::Frame;
use Cro::WebSocket::Message;

class Cro::WebSocket::MessageSerializer does Cro::Transform {
    method consumes() { Cro::WebSocket::Message }
    method produces() { Cro::WebSocket::Frame }

    method transformer(Supply:D $in) {
        supply {
            my @order = ();
            my $current = Nil;
            my Bool $first = True;

            sub set-current() {
                return if @order.elems == 0;
                return if $current;

                $current = @order.shift;
                whenever $current.body-byte-stream -> $payload {
                    my $opcode = $first
                                 ?? Cro::WebSocket::Frame::Opcode($current.opcode.value)
                                 !! Cro::WebSocket::Frame::Continuation;
                    $first = False;
                    emit Cro::WebSocket::Frame.new(fin => !$current.fragmented, :$opcode, :$payload);
                    LAST {
                        emit Cro::WebSocket::Frame.new(fin => True,
                                                       opcode => Cro::WebSocket::Frame::Continuation,
                                                       payload => Blob.new()) if $current.fragmented;
                        $first = True; $current = Nil;
                        set-current;
                    }
                }
            }

            whenever $in -> Cro::WebSocket::Message $m {
                my $opcode = $m.opcode // -1;
                if $opcode == 8|9|10 {
                    emit Cro::WebSocket::Frame.new(fin => True,
                                                   opcode => Cro::WebSocket::Frame::Opcode($opcode.value),
                                                   payload => $m.body-blob.result);
                } else {
                    @order.push: $m;
                    set-current;
                }
            }
        }
    }
}
