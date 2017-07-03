use Cro::TCP;
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

            sub extract(@data, $size, &command, $expect --> Bool) {
                if @data.elems + @buffer.elems < $size {
                    @buffer.append: @data; False;
                } else {
                    @data.prepend: @buffer;
                    @buffer = ();
                    &command(@data);
                    # eat up taken bits
                    @data = @data[$size..*];
                    $expecting = $expect;
                    True;
                }
            }

            whenever $in -> Cro::TCP::Message $packet {
                sub extend(@bits) {
                    if @bits.elems != 8 {
                        my @prefix = 0 xx (8 - @bits.elems);
                        @prefix.append: @bits;
                    } else {
                        @bits;
                    }
                }
                my Int @data = $packet.data.map({ extend($_.base(2).comb) }).flat.map({.Int});
                loop {
                    $_ = $expecting;
                    when Fin {
                        # We cannot get less than 1 bit here
                        $frame.fin = @data[0] == 1 ?? True !! False;
                        @data = @data[1..*];
                        $expecting = Reserve;
                        next;
                    }
                    when Reserve {
                        # Three bits
                        last unless extract(@data, 3, -> @_ {}, Op); next;
                    }
                    when Op {
                        # Four bits
                        my &comm = -> @_ { $frame.opcode = Cro::WebSocket::Frame::Opcode("0b{@_[0..3].Str.subst(' ', '', :g)}".Int) };
                        last unless extract(@data, 4, &comm, MaskBit); next;
                    }
                    when MaskBit {
                        $mask-flag = @data[0] == 1 ?? True !! False;
                        die X::Cro::WebSocket::IncorrectMaskFlag.new if $!mask-required !== $mask-flag;
                        @data = @data[1..*];
                        $expecting = Length; next;
                    }
                    when Length {
                        # 7 | 7+16 | 7+64 bits
                        my &comm = -> @_ {
                            my $baselen = "0b{@_[0..6].Str.subst(' ', '', :g)}".Int;
                            if $baselen < 126 {
                                $length = $baselen; $expecting = MaskKey;
                            } elsif $baselen < 127 {
                                my &comm = -> @_ { $length = "0b{@_[0..15].Str.subst(' ', '', :g)}".Int };
                                last unless extract(@data, 16, &comm, MaskKey);
                            } else {
                                my &comm = -> @_ { $length = "0b{@_[0..63].Str.subst(' ', '', :g)}".Int };
                                last unless extract(@data, 64, &comm, MaskKey);
                            }
                        };
                        last unless extract(@data, 7, &comm, MaskKey); next;
                    }
                    when MaskKey {
                        unless $mask-flag { $expecting = Payload; next };
                        my &comm = -> @_ { @mask = @_[0..31] };
                        last unless extract(@data, 32, &comm, Payload); next;
                    }
                    when Payload {
                        if $length == 0 {
                            emit $frame;
                        } else {
                            # In case something is buffered;
                            @data.prepend: @buffer;
                            if @data.elems == $length * 8 {
                                my $payload = $mask-flag ?? (@data Z+^ (@mask xx *).flat).Array !! @data;
                                $frame.payload = Blob.new(self!to-bytes($payload));
                                emit $frame;
                            } else {
                                my Int $entire = @data.elems div 8;
                                for $entire {
                                    @buffer.append: @data;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    method !to-bytes(@data) {
        my @result;
        my $counter = @data.elems div 8;
        for 1..$counter {
            @result.append: "0b{@data[0..7].Str.subst(' ', '', :g)}".Int;
            @data = @data[8..*];
        }
        @result;
    }
}
