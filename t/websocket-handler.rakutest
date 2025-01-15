use Cro::WebSocket::Handler;
use Cro::WebSocket::Message;
use Test;

my $completion = Promise.new;

my $uc-ws = Cro::WebSocket::Handler.new(
    -> $incoming {
        supply {
            whenever $incoming -> $message {
                my $body = await $message.body-text();
                emit Cro::WebSocket::Message.new($body.uc);
            }
        }
    }
);

my $fake-in = Supplier.new;

$uc-ws.transformer($fake-in.Supply).tap: -> $resp {
    my $text = $resp.body-text.result if $resp.opcode != Cro::WebSocket::Message::Close;

    with $text {
        ok $text eq $text.uc;
    }
    $completion.keep;
};

$fake-in.emit(Cro::WebSocket::Message.new('Up me'));

await Promise.anyof($completion, Promise.in(5));

unless $completion.status ~~ Kept {
    flunk "Handler without close promise passed doesn't work";
}

my Int $count = 4;
my Int $counter = 0;

$completion = Promise.new;

$uc-ws = Cro::WebSocket::Handler.new(
    -> $incoming, $close {
        supply {
            whenever $incoming -> $message {
                my $body = await $message.body-text();
                emit Cro::WebSocket::Message.new($body.uc);
            }
            whenever $close -> $message {
                my $blob = $message.body-blob.result;
                my Int $code = ($blob[0] +< 8) +| $blob[1];
                ok $code == 1000, 'Close code is 1000';
                $completion.keep if $count == $counter;
            }
        }
    }
);

$fake-in = Supplier.new;

$uc-ws.transformer($fake-in.Supply).tap: -> $resp {
    my $text = $resp.body-text.result if $resp.opcode !=
      Cro::WebSocket::Message::Close|Cro::WebSocket::Message::Pong;
    with $text {
        ok $text eq $text.uc;
    }
    $counter++;
};

$fake-in.emit(Cro::WebSocket::Message.new('First Test'));

$fake-in.emit(Cro::WebSocket::Message.new('Second Test'));

$fake-in.emit(Cro::WebSocket::Message.new(opcode => Cro::WebSocket::Message::Ping,
                                          fragmented => False,
                                          body-byte-stream => supply
                                                           { emit 'ping'.encode }));

$fake-in.emit(Cro::WebSocket::Message.new(opcode => Cro::WebSocket::Message::Close,
                                          fragmented => False,
                                          body-byte-stream => supply   # 1000
                                                           { emit Blob.new(3, 232) }));

await Promise.anyof($completion, Promise.in(5));

unless $completion.status ~~ Kept {
    flunk "Handler with close promise passed doesn't work";
}

done-testing;
