use Cro::TCP;
use Cro::WebSocket::Frame;
use Cro::Transform;

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
            my enum Expecting <FinOp MaskLength Length2 Length3 MaskKey Payload>;

            my Expecting $expecting = FinOp;
            my Bool $mask-flag;
            my Buf $mask;
            my $frame = Cro::WebSocket::Frame.new;
            my Buf $buffer = Buf.new;
            my Int $length;

            whenever $in -> Cro::TCP::Message $packet {
                my Blob $data = $packet.data;
                $data = $buffer ~ $data;
                $buffer = Buf.new;

                loop {
                    last if $data eq Blob.new && $expecting !== Payload|MaskKey;
                    $_ = $expecting;

                    when FinOp {
                        $frame.fin = self!check-first-bit($data[0]); # Check first bit.
                        $frame.opcode = Cro::WebSocket::Frame::Opcode($data[0] +& 15); # Last 4 bits.
                        $data .= subbuf(1);
                        $expecting = MaskLength;
                        next;
                    }
                    when MaskLength {
                        last if $data.elems < 1;
                        $mask-flag = self!check-first-bit($data[0]);
                        die X::Cro::WebSocket::IncorrectMaskFlag.new if $!mask-required !== $mask-flag;
                        my $baselen = $data[0] +& 127;
                        # Drop baselen byte;
                        $data .= subbuf(1);
                        if $baselen < 126 {
                            $length = $baselen;
                            $expecting = MaskKey; next;
                        } elsif $baselen < 127 {
                            $expecting = Length2; next;
                        } else {
                            $expecting = Length3; next;
                        }
                    }
                    when Length2 {
                        if $data.elems < 2 {
                            $buffer.append: $data; last;
                        } else {
                            die 'Length cannot be negative' if self!check-first-bit($data[0]);
                            $length = ($data[0] +< 8) +| $data[1];
                            $data .= subbuf(2);
                            $expecting = MaskKey; next;
                        }
                    }
                    when Length3 {
                        if $data.elems < 8 {
                            $buffer.append: $data; last;
                        } else {
                            die 'Length cannot be negative' if self!check-first-bit($data[0]);
                            $length = 0;
                            loop (my $i = 0; $i < 8; $i++) {
                                $length = $length +< 8 +| $data[$i];
                            };
                            $data .= subbuf(8);
                            $expecting = MaskKey; next;
                        }
                    }
                    when MaskKey {
                        if $mask-flag {
                            if $data.elems < 4 {
                                $buffer.append: $data; last;
                            }
                            $mask = $data.subbuf(0,4);
                            $data .= subbuf(4);
                        }
                        $expecting = Payload;
                        next;
                    }
                    when Payload {
                        if $length == 0 {
                            $frame.payload = Blob.new;
                            $expecting = FinOp;
                            emit $frame;
                        } else {
                            if $data.elems >= $length {
                                my $payload = $data.subbuf(0, $length);
                                $payload = $mask-flag ?? Blob.new((@$payload Z+^ (@$mask xx *).flat)) !! $payload;
                                $frame.payload = Blob.new: $payload;
                                $data .= subbuf($length);
                                $expecting = FinOp;
                                emit $frame; next if $data.elems > 0;
                            } else {
                                $buffer.append: $data;
                            }
                        }
                    }
                }
                LAST {
                    die X::Cro::WebSocket::Disconnect.new if $expecting != FinOp;
                }
            }
        }
    }

    method !check-first-bit(Int $byte --> Bool) {
        $byte +& (1 +< 7) != 0
    }
}
