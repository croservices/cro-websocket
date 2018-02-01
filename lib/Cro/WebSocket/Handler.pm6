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

            my class CloseMessage {
                has $.message;
            }
            my $block-feed = $supplier.Supply.Channel.Supply.grep: -> $msg {
                if $msg ~~ CloseMessage {
                    $msg.defined
                        ?? keep-close-promise($msg.message)
                        !! keep-close-promise();
                    False
                }
                else {
                    True
                }
            }
            my $block = &!block.count == 1
                        ?? &!block($block-feed)
                        !! &!block($block-feed, $on-close);

            sub close(Bool $end, Blob $code) {
                unless $end {
                    emit Cro::WebSocket::Message.new(
                        opcode => Cro::WebSocket::Message::Close,
                        fragmented => False,
                        body-byte-stream => supply { emit $code });
                    $supplier.emit(CloseMessage);
                    done;
                }
            }

            whenever $block {
                when Cro::WebSocket::Message {
                    emit $_;
                    if .opcode == Cro::WebSocket::Message::Close {
                        $supplier.emit(CloseMessage);
                        $end = True;
                        done;
                    }
                }
                default {
                    emit Cro::WebSocket::Message.new($_)
                }

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
                            $supplier.emit(CloseMessage.new(message => $m));
                            $supplier.done;
                        }
                        default {}
                    }
                }
            }
        }
    }
}
