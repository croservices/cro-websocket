use Cro::WebSocket::Frame;
use Cro::Transform;

class X::Cro::WebSocket::IncorrectMaskFlag is Exception {
    method message() {
        "Mask flag of the FrameParser instance and the current frame flag differ"
    }
}

class Cro::WebSocket::FrameParser does Cro::Transform {
    has Bool $.mask-required;

    method consumes() { Cro::TCP::Message }
    method produces() { Cro::WebSocket::Frame }

    method transformer(Supply:D $in) {
        supply {
            my enum Expecting <Fin Reserve Op MaskBit Length MaskKey Payload>;

            my Expecting $expecting = Fin;
            my Bool $mask-flag;
            my Int @mask;
            my $frame = Cro::WebSocket::Frame.new;
            my Int @trail;
            my Int @buffer;
            my Int $length;

            sub extract(@data, $size, &command, $expect --> Buf) {
                if @data.elems + @buffer.elems < $side {
                    @buffer.append: @data; False;
                } else {
                    @data.prepend: @buffer;
                    @buffer = ();
                    $command(@data);
                    # eat up taken bits
                    @data = @data[$size-1..*];
                    $expecting = $expect;
                    True;
                }
            }

            whenever $in -> Cro::TCP::Message $packet {
                my Blob @data = $packet.data.map({ .base(2).comb }).flat;
                loop {
                    $_ = $expecting;
                    when Fin {
                        # We cannot get less than 1 bit here
                        $frame.fin = @data[0];
                        @data = @data[1..];
                        $expecting = Reserve;
                    }
                    when Reserve {
                        # Three bits
                        last unless extract(@data, 3, {}, Op);
                    }
                    when Op {
                        # Four bits
                        my &comm = { $frame.opcode = "0b{@_[0..3].Str.subst(' ', '', :g)}".Int };
                        last unless extract(@data, 4, &comm, MaskBit);
                    }
                    when MaskBit {
                        $mask-flag = @data[0] == 1 ?? True !! False;
                        die X::Cro::WebSocket::IncorrectMaskFlag.new if $!mask-flag !== $mask-flag;
                        @data = @data[1..];
                        $expecting = Length;
                    }
                    when Length {
                        # 7 | 7+16 | 7+64 bits
                        my &comm = {
                            my $baselen = "0b{@_[0..6].Str.subst(' ', '', :g)}".Int;
                            if $baselen < 126 {
                                $length = $baselen; $expecting = MaskKey; last;
                            } elsif $baselen < 127 {
                                my &comm = { $length = "0b{@_[0..15].Str.subst(' ', '', :g)}".Int };
                                last unless extract(@data, 16, &comm, MaskKey);
                            } else {
                                my &comm = { $length = "0b{@_[0..63].Str.subst(' ', '', :g)}".Int };
                                last unless extract(@data, 64, &comm, MaskKey);
                            }
                        };
                        last unless extract(@data, 7, &comm, MaskKey);
                    }
                    when MaskKey {
                        unless $mask-flag { $expected = Payload; next };
                        my &comm = { @mask = @_[0..31] };
                        last unless extract(@data, 32, &comm, Payload);
                    }
                    when Payload {
                        if $length == 0 {
                            emit $frame;
                        } else {
                            if @buffer.elems == $length {
                                my $payload = $mask-flag ?? @data Z+^ (@mask xx *).flat !! @buffer;
                                $frame.payload = Blob.new(@buffer);
                                emit $frame;
                            } else {
                                @data.prepend: @trail;
                                my Int $entire = @data.elems div 8;
                                for $entire {
                                    # very inefficient
                                    @buffer.append(self!take-byte(@data));
                                }
                                # Gather trailing bits
                                @trail = @data;
                            }
                        }
                    }
                }
            }
        }
    }

    method !take-byte(@data, @buffer) {
        @buffer.append: "0b{@data[0..7].Str.subst(' ', '', :g)}".Int;
         @data = @data[7..*];
    }
}
