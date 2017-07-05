use Cro::Transform;
use Cro::WebSocket::Message;

class Cro::WebSocket::Handler does Cro::Transform {
    has $.block;

    method consumes() { Cro::WebSocket::Message }
    method produces() { Cro::WebSocket::Message }

    method new($block) {
        return self.bless(:$block);
    }

    method transformer(Supply:D $in) {
        supply {
            my $supplier = Supplier::Preserving.new;
            my $promise = Promise.new if $!block.count == 2;
            my $end = False;

            my $block = $!block.count == 1
                        ?? $!block($supplier.Supply)
                        !! $!block($supplier.Supply, $promise);

            whenever $block {
                when Cro::WebSocket::Message {
                    emit $resp;
                    if $resp.opcode == Cro::WebSocket::Message::Close {
                        $end = True;
                        done;
                    }
                }
                when Blob|Str|Supply { emit Cro::WebSocket::Message.new($resp) }

                LAST {
                    unless $end {
                        emit Cro::WebSocket::Message.new(opcode => Cro::WebSocket::Message::Close,
                                                         fragmented => False,
                                                         body-byte-stream => supply   # 1000
                                                                          { emit Blob.new(3, 232) });
                    }
                    done;
                }
                QUIT {
                    unless $end {
                        emit Cro::WebSocket::Message.new(opcode => Cro::WebSocket::Message::Close,
                                                         fragmented => False,
                                                         body-byte-stream => supply   # 1011
                                                                          { emit Blob.new(3, 243) });
                    }
                    done;
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
                                                             body-byte-stream => await($m.body-blob));
                        }
                        when Cro::WebSocket::Message::Close {
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
