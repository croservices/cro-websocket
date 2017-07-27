use Cro::Transform;
use Cro::WebSocket::Message;

class Cro::WebSocket::Handler does Cro::Transform {
    has &.block;

    method consumes() { Cro::WebSocket::Message }
    method produces() { Cro::WebSocket::Message }

    method new(&block) {
        return self.bless(:&block);
    }

    method transformer(Supply:D $in) {
        supply {
            my $supplier = Supplier::Preserving.new;
            my $on-close = Promise.new if &!block.count == 2;
            my $on-close-vow = $on-close.?vow;
            my $end = False;

            sub keep-close-promise($m = Nil) {
                with $on-close-vow {
                    $on-close-vow.keep($m);
                    $on-close-vow = Nil;
                }
            }

            my $block = &!block.count == 1
                        ?? &!block($supplier.Supply)
                        !! &!block($supplier.Supply, $on-close);

            whenever $block {
                sub close(Bool $end, Blob $code) {
                    unless $end {
                        emit Cro::WebSocket::Message.new(
                            opcode => Cro::WebSocket::Message::Close,
                            fragmented => False,
                            body-byte-stream => supply { emit $code });
                        keep-close-promise();
                        done;
                    }
                }

                when Cro::WebSocket::Message {
                    emit $_;
                    if $_.opcode == Cro::WebSocket::Message::Close {
                        keep-close-promise();
                        $end = True;
                        done;
                    }
                }
                when Blob|Str|Supply { emit Cro::WebSocket::Message.new($_) }

                LAST {
                    close($end, Blob.new([3, 232])); # bytes of 1000
                }
                QUIT {
                    close($end, Blob.new([3, 343])); # bytes of 1011
                }
            }

            whenever $in -> Cro::WebSocket::Message $m {
                if $m.is-data {
                    $supplier.emit($m);
                } else {
                    given $m.opcode {
                        when Cro::WebSocket::Message::Ping {
                            emit Cro::WebSocket::Message.new(
                                opcode => Cro::WebSocket::Message::Pong,
                                fragmented => False,
                                body-byte-stream => supply {
                                    emit (await $m.body-blob);
                                    done;
                                });
                        }
                        when Cro::WebSocket::Message::Close {
                            emit Cro::WebSocket::Message.new(
                                opcode => Cro::WebSocket::Message::Close,
                                fragmented => False,
                                body-byte-stream => supply {
                                    emit (await $m.body-blob);
                                    done;
                                });
                            keep-close-promise($m);
                            $supplier.done;
                        }
                        default {}
                    }
                }
            }
        }
    }
}
