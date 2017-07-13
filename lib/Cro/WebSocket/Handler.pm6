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
            my $close-response = Promise.new;

            my $block = &!block.count == 1
                        ?? &!block($supplier.Supply)
                        !! &!block($supplier.Supply, $promise);

            whenever $block {
                sub close(Bool $end, Blob $code, $close-p, $promise) {
                    unless $end {
                        emit Cro::WebSocket::Message.new(opcode => Cro::WebSocket::Message::Close,
                                                         fragmented => False,
                                                         body-byte-stream => supply { emit $code });
                        # 2 seconds timeout
                        await Promise.anyof($close-p, Promise.in(2));
                        $promise.keep if $promise;
                        done;
                    }
                }

                when Cro::WebSocket::Message {
                    emit $_;
                    if $_.opcode == Cro::WebSocket::Message::Close {
                        $promise.keep if $promise;
                        $end = True;
                        # 2 seconds timeout
                        await Promise.anyof($close-response, Promise.in(2));
                        done;
                    }
                }
                when Blob|Str|Supply { emit Cro::WebSocket::Message.new($_) }

                LAST {
                    close($end, Blob.new([3, 232]), $close-response, $promise); # bytes of 1000
                }
                QUIT {
                    close($end, Blob.new([3, 343]), $close-response, $promise); # bytes of 1011
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
                            $close-response.keep;
                            $supplier.done;
                        }
                        default {}
                    }
                }
            }
        }
    }
}
