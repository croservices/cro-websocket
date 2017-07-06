use Cro::WebSocket::Handler;
use Cro::WebSocket::Message;
use Test;

my Int $count = 3;

my $uc-ws = Cro::WebSocket::Handler.new(
    -> $incoming, $close {
        supply {
            whenever $incoming -> $message {
                my $body = await $message.body-text();
                emit Cro::WebSocket::Message.new($body.uc);
            }
            whenever $close -> $message {
                say "Close body: " ~ await($message.body-blob).gist;
            }
        }
    }
);

my $fake-in = Supplier.new;
my $completion = Promise.new;
my Int $counter = 0;

$uc-ws.transformer($fake-in.Supply).tap: -> $resp {
    my $text = $resp.body-text.result if $resp.opcode != Cro::WebSocket::Message::Close;
    with $text {
        ok $text eq $text.uc;
    }
    $counter++;
    $completion.keep if $count == $counter;
};

$fake-in.emit(Cro::WebSocket::Message.new('First Test'));

$fake-in.emit(Cro::WebSocket::Message.new('Second Test'));

$fake-in.emit(Cro::WebSocket::Message.new(opcode => Cro::WebSocket::Message::Close,
                                          fragmented => False,
                                          body-byte-stream => supply   # 1000
                                                           { emit Blob.new(3, 232) }));

await $completion;

done-testing;
