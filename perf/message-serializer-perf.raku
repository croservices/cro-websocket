use Cro::WebSocket::MessageSerializer;
use Cro::WebSocket::Message;
use Cro::WebSocket::Message::Opcode;


multi make-message(Str:D $message) {
    Cro::WebSocket::Message.new($message)
}

multi make-message($opcode, &generate, :$fragmented = $opcode <= Binary) {
    Cro::WebSocket::Message.new(:$opcode, :$fragmented, body-byte-stream => generate())
}

my @random-data = 255.rand.Int xx 65536;

my @messages =
\('First Test'),
\('Second Test'),
\(Text,   { supply { emit 'Hel'.encode; emit 'lo'.encode; done; } }),
\(Ping,   { supply { emit 'Ping'.encode; done; } }),
\(Close,  { supply { emit Blob.new(3, 232); done } }),
\(Binary, { supply { emit Blob.new(@random-data); done } }),
;


my $repeat      = @*ARGS[0] // 1_000;
my $expected    = 8;
my $frames      = $repeat * $expected;
my @tests       = @messages.map: -> $c { |( make-message(|$c) for ^$repeat) };
my $serializer  = Cro::WebSocket::MessageSerializer.new;
my $fake-in     = Supplier.new;
my $complete    = Promise.new;
my atomicint $i = 0;

my $t0 = now;

$serializer.transformer($fake-in.Supply).tap: -> $frame {
    die "Did not parse as a WebSocket frame" unless $frame ~~ Cro::WebSocket::Frame;
    $complete.keep if ++⚛$i == $frames;
}
start {
    for @tests { $fake-in.emit($_) }
    $fake-in.done;
}
await $complete;

my $t1 = now;
my $delta = $t1 - $t0;

printf "MESSAGES:  %6d in %.3fs = %.3fms ave\n",
       +@tests, $delta, 1000 * $delta / @tests;
printf "FRAMES:    %6d in %.3fs = %.3fms ave\n",
       $frames, $delta, 1000 * $delta / $frames;
