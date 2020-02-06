use Cro::TCP;
use Cro::WebSocket::Frame;
use Cro::Transform;

class X::Cro::WebSocket::PayloadLengthTooLarge is Exception {
    method message() {
        "WebSocket frame 8-byte extended payload lengths cannot have the high bit set"
    }
}

class X::Cro::WebSocket::IncorrectMaskFlag is Exception {
    method message() {
        "Mask flag of the FrameParser instance and the current frame flag differ"
    }
}

class X::Cro::WebSocket::Disconnect is Exception {
    method message() { "Connection unexpectedly closed in the middle of frame" }
}

class Cro::WebSocket::FrameParser does Cro::Transform {
    has Bool $.mask-required;

    method consumes() { Cro::TCP::Message }
    method produces() { Cro::WebSocket::Frame }

    method transformer(Supply:D $in) {
        supply {
            my Buf $buffer .= new;

            my sub emit-frame($mask-flag, $payload-len, $pos) {
                my $frame     = Cro::WebSocket::Frame.new;
                my $fin-op    = $buffer[0];
                $frame.fin    = ?($fin-op +& 128);
                $frame.opcode = Cro::WebSocket::Frame::Opcode($fin-op +& 15);

                if $mask-flag {
                    my $mask       = $buffer.subbuf($pos, 4);
                    $frame.payload = $buffer.subbuf($pos + 4, $payload-len)
                                     ~^ Blob.allocate($payload-len, $mask);
                }
                else {
                    $frame.payload = $buffer.subbuf($pos, $payload-len);
                }

                emit $frame;
            }

            whenever $in -> Cro::TCP::Message $packet {
                $buffer ~= $packet.data;

                # Loop in case TCP message contained data from multiple frames
                loop {
                    # Smallest valid frame is 2 bytes: fin-op and mask-len
                    last if (my $buf-len = $buffer.elems) < 2;

                    my $mask-len  = $buffer[1];
                    my $mask-flag = ?($mask-len +& 128);
                    die X::Cro::WebSocket::IncorrectMaskFlag.new
                        if $!mask-required != $mask-flag;
                    my $base-len  =   $mask-len +& 127;

                    if $base-len < 126 {
                        my $min-len = 2 + $mask-flag * 4 + $base-len;
                        last if $buf-len < $min-len;

                        emit-frame($mask-flag, $base-len, 2);
                        $buffer .= subbuf($min-len);
                    }
                    elsif $base-len == 126 {
                        last if $buf-len < 4;

                        my $payload-len = $buffer.read-uint16(2, BigEndian);
                        my $min-len     = 4 + $mask-flag * 4 + $payload-len;
                        last if $buf-len < $min-len;

                        emit-frame($mask-flag, $payload-len, 4);
                        $buffer .= subbuf($min-len);
                    }
                    else {
                        last if $buf-len < 10;
                        die X::Cro::WebSocket::PayloadLengthTooLarge.new
                            if $buffer[2] +& 128;

                        my $payload-len = $buffer.read-uint64(2, BigEndian);
                        my $min-len     = 10 + $mask-flag * 4 + $payload-len;
                        last if $buf-len < $min-len;

                        emit-frame($mask-flag, $payload-len, 10);
                        $buffer .= subbuf($min-len);
                    }
                }

                LAST {
                    die X::Cro::WebSocket::Disconnect.new if $buffer;
                }
            }
        }
    }
}
