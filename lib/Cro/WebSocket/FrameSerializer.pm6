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
                my Buf $message = Buf.new;
                my Int $i = 0;
                # Set final flag
                $message[$i] = $frame.fin ?? 128 !! 0;
                # Set opcode
                $message[$i] = $message[0] +| $frame.opcode.value;
                $i++;

                # Set mask & payload length
                $message[$i] = $!mask ?? 128 !! 0;
                my $length = self!calculate-length($frame.payload.elems);
                $message[$i] = $message[1] +| $length;
                $i++;

                # Extended length
                if $length == 126 {
                    $message[$i] = ($frame.payload.elems +> 8) +& 0xFF; $i++;
                    $message[$i] =  $frame.payload.elems       +& 0xFF; $i++;
                } elsif $length == 127 {
                    for 56,48...0 { # Up from 56
                        $message[$i] = ($frame.payload.elems +> $_) +& 0xFF; $i++;
                    }
                }

                # Mask
                if $!mask {
                    my $mask-buf = crypt_random_buf(4);
                    for @$mask-buf -> $byte {
                        $message[$i] = $byte; $i++;
                    }
                    my $payload = Blob.new((@($frame.payload) Z+^ ((@$mask-buf xx *).flat)).Array);
                    emit Cro::TCP::Message.new(data => $message.append: $payload);
                } else {
                    emit Cro::TCP::Message.new(data => $message.append: $frame.payload);
                }
            }
        }
    }

    method !calculate-length($len) {
        if    $len < 126     { $len }
        elsif $len < 2 ** 16 { 126  }
        elsif $len < 2 ** 64 { 127  }
    }
}
