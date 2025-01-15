use Cro::TCP;
use Cro::WebSocket::Frame;
use Cro::Transform;
use Crypt::Random;

class Cro::WebSocket::FrameSerializer does Cro::Transform {
    has Bool $.mask;

    method consumes() { Cro::WebSocket::Frame }
    method produces() { Cro::TCP::Message }

    method transformer(Supply:D $in) {
        supply {
            whenever $in -> Cro::WebSocket::Frame $frame {
                my $message = Buf.new;

                # Fin flag and opcode
                $message[0] = ($frame.fin ?? 128 !! 0) + $frame.opcode.value;

                # Mask flag and payload length
                my $payload-len = $frame.payload.elems;
                my $pos;
                if $payload-len < 126 {
                    $message[1] = ($!mask ?? 128 !! 0) + $payload-len;
                }
                elsif $payload-len < 65536 {
                    $message[1] = $!mask ?? 254 !! 126;
                    $message.write-uint16(2, $payload-len, BigEndian);
                }
                elsif $payload-len < 2 ** 63 {
                    $message[1] = $!mask ?? 255 !! 127;
                    $message.write-uint64(2, $payload-len, BigEndian);
                }
                else {
                    die "Payload length $payload-len too large for a WebSocket frame";
                }

                # Mask and payload
                if $!mask {
                    my $mask-buf = crypt_random_buf(4);
                    $message.append: $mask-buf;
                    my $payload = $frame.payload ~^ Blob.allocate($frame.payload.elems, $mask-buf);
                    emit Cro::TCP::Message.new(data => $message.append: $payload);
                } else {
                    emit Cro::TCP::Message.new(data => $message.append: $frame.payload);
                }
            }
        }
    }
}
