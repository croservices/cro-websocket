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
            my $promise = Promise.new if &!block.count == 2;
            my $end = False;

            my $block = &!block.count == 1
                        ?? &!block($supplier.Supply)
                        !! &!block($supplier.Supply, $promise);

            whenever $block {
                sub close(Bool $end, Blob $code, $promise) {
                    unless $end {
                        emit Cro::WebSocket::Message.new(opcode => Cro::WebSocket::Message::Close,
                                                         fragmented => False,
                                                         body-byte-stream => supply { emit $code });
                        $promise.keep if $promise;
                        done;
                    }
                }

                when Cro::WebSocket::Message {
                    emit $_;
                    if $_.opcode == Cro::WebSocket::Message::Close {
                        $promise.keep if $promise;
                        $end = True;
                        done;
                    }
                }
                when Blob|Str|Supply { emit Cro::WebSocket::Message.new($_) }

                LAST {
                    close($end, Blob.new([3, 232]), $promise); # bytes of 1000
                }
                QUIT {
                    close($end, Blob.new([3, 343]), $promise); # bytes of 1011
                }
            }

            whenever $in -> Cro::WebSocket::Message $m {
                if $m.is-data {
                    $supplier.emit($m);
                } else {
                    given $m.opcode {
                        when Cro::WebSocket::Message::Ping {
                            emit Cro::WebSocket::Message.new(opcode => Cro::WebSocket::Message::Pong,
                                                             fragmented => False,
                                                             body-byte-stream => supply {
                                                                    emit (await $m.body-blob);
                                                                    done;
                                                                });
                        }
                        when Cro::WebSocket::Message::Close {
                            emit Cro::WebSocket::Message.new(opcode => Cro::WebSocket::Message::Close,
                                                             fragmented => False,
                                                             body-byte-stream => supply {
                                                                    emit (await $m.body-blob);
                                                                    done;
                                                                });
                            with $promise { .keep($m) }
                            $supplier.done;
                        }
                        default {}
                    }
                }
            }
        }
    }
}
