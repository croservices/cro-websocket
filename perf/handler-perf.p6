use Cro::WebSocket::Handler;
use Cro::WebSocket::Message;
use Cro::WebSocket::Message::Opcode;

my $uc-ws = Cro::WebSocket::Handler.new(
    -> $incoming {
        supply {
            whenever $incoming -> $message {
                my $body = await $message.body-text;
                emit Cro::WebSocket::Message.new($body.uc);
            }
        }
    }
);

multi make-message(Str:D $message) {
    Cro::WebSocket::Message.new($message)
}

multi make-message($opcode, &generate) {
    Cro::WebSocket::Message.new(:$opcode, :!fragmented, body-byte-stream => generate())
}

my @messages =
\('First Test'),
\('Second Test'),
\(Ping,  { supply { emit 'ping'.encode    } }),
\(Close, { supply { emit Blob.new(3, 232) } }),
;

my $repeat      = @*ARGS[0] // 10_000;
my @tests       = @messages.map: -> $c { |( make-message(|$c) for ^$repeat) };
my $fake-in     = Supplier.new;
my $complete    = Promise.new;
my atomicint $i = 0;

my $t0 = now;

$uc-ws.transformer($fake-in.Supply).tap: -> $resp {
    die "Did not respond with a WebSocket message"
        unless $resp ~~ Cro::WebSocket::Message;
    $complete.keep if ++⚛$i == @tests;
}
start {
    for @tests { $fake-in.emit($_) }
    $fake-in.done;
}
await $complete;

my $t1 = now;
my $delta = $t1 - $t0;

printf "RESPONSES: %6d in %.3fs = %.3fms ave\n",
       +@tests,   $delta, 1000 * $delta / @tests;
