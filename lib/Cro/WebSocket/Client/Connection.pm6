use Cro;
use Cro::TCP;
use Cro::WebSocket::FrameParser;
use Cro::WebSocket::FrameSerializer;
use Cro::WebSocket::Message;
use Cro::WebSocket::MessageParser;
use Cro::WebSocket::MessageSerializer;

class Cro::WebSocket::Client::Connection {
    has Supply $.in;
    has Supplier $.out;
    has Supplier $.sender;
    has Supply $.receiver;
    has Promise $.closer;

    method new(:$in, :$out) {
        my $sender = Supplier.new;
        my $receiver = Supplier.new;
        my $closer = Promise.new;

        my $pp-in = Cro.compose(Cro::WebSocket::FrameParser.new(mask-required => False),
                                Cro::WebSocket::MessageParser.new
                               ).transformer($in.map(-> $data { Cro::TCP::Message.new(:$data) }));

        my $pp-out = Cro.compose(Cro::WebSocket::MessageSerializer.new,
                                 Cro::WebSocket::FrameSerializer.new(mask => True)
                                ).transformer($sender.Supply);

        $pp-in.tap(-> $_ {
                          if .is-data {
                              $receiver.emit: $_;
                          } else {
                              when $_.opcode == Cro::WebSocket::Message::Ping {
                                  my $body-byte-stream = $_.body-byte-stream;
                                  my $m = Cro::WebSocket::Message.new(opcode => Cro::WebSocket::Message::Pong,
                                                                      fragmented => False,
                                                                      :$body-byte-stream);
                                  $sender.emit: $m;
                              }
                              when $_.opcode == Cro::WebSocket::Message::Pong {
                                  # Factory of promises closing?
                              }
                              when $_.opcode == Cro::WebSocket::Message::Close {
                                  $closer.keep($_);
                                  self.close(1000);
                              }
                          }
                      });
        $pp-out.tap(-> $_ {
                           $out.emit: $_.data;
                       });

        self.bless(:$in, :$out, :$sender, receiver => $receiver.Supply, :$closer);
    }

    method messages(--> Supply) {
        $!receiver;
    }

    multi method send(Cro::WebSocket::Message $m) {
        $!sender.emit($m);
    }
    multi method send($m) {
        die 'Expecting message-like type, $m was sent' unless $m ~~ Str|Blob|Supply;
        self.send(Cro::WebSocket::Message.new($m));
    }

    method close($code = 1000, :$timeout --> Promise) {
        my $p = Promise.new;

        start {
            my $message = Cro::WebSocket::Message.new(opcode => Cro::WebSocket::Message::Close,
                                                      fragmented => False,
                                                      body-byte-stream => supply   # 1000
                                                                       { emit Blob.new(3, 232) });

            my $real-timeout = $timeout // 2; 
            if $timeout == False || $timeout == 0 {
                $!sender.emit: $message;
                $!sender.done;
            } else {
                await Promise.anyof(Promise.in($timeout), $!closer);
                if $!closer.status == Kept {
                    $p.keep($!closer.result);
                } else {
                    my $close-m = Cro::WebSocket::Message.new(opcode => Cro::WebSocket::Message::Close,
                                                              fragmented => False,
                                                              body-byte-stream => supply   # 1006
                                                                               { emit Blob.new(3, 248) });
                    $p.break($close-m);
                }
            }
        }
        $p;
    }

    method ping($data?, :$timeout --> Promise) {
        # Factory of promises?
        my $p = Promise.new;

        $!sender.emit(Cro::WebSocket::Message.new(opcode => Cro::WebSocket::Message::Ping,
                                                  fragmented => False,
                                                  body-byte-stream => supply {
                                                         emit $data if $data;
                                                         done; }));
        $p;
    }
}
