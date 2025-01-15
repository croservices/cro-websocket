use Cro::WebSocket::MessageParser;

constant Cont   = Cro::WebSocket::Frame::Continuation;
constant Text   = Cro::WebSocket::Frame::Text;
constant Binary = Cro::WebSocket::Frame::Binary;
constant Close  = Cro::WebSocket::Frame::Close;
constant Ping   = Cro::WebSocket::Frame::Ping;
constant Pong   = Cro::WebSocket::Frame::Pong;

multi make-frame($opcode, Str:D $payload, Bool:D $fin = $opcode >= Close) {
    Cro::WebSocket::Frame.new(:$opcode, :$fin, payload => $payload.encode)
}

multi make-frame($opcode, $payload, Bool:D $fin = $opcode >= Close) {
    Cro::WebSocket::Frame.new(:$opcode, :$fin, payload => Blob.new($payload))
}

my @random-data = 255.rand.Int xx 65536;

my @frames =
\(Text,  'Hello', True),
\(Text,  'Hel'),
\(Cont,  'lo', True),
\(Ping,  'Hello'),
\(Binary, @random-data[0..75]),
\(Cont,   @random-data[75^..^173]),
\(Cont,   @random-data[173..255], True),
\(Binary, @random-data[0..255], True),
\(Binary, @random-data, True),
;

my $repeat      = @*ARGS[0] // 10_000;
my $expected    = 6;
my $messages    = $repeat * $expected;
my @tests       = @frames.map: -> $c { |( make-frame(|$c) for ^$repeat) };
my $parser      = Cro::WebSocket::MessageParser.new;
my $fake-in     = Supplier.new;
my $complete    = Promise.new;
my atomicint $i = 0;

my $t0 = now;

$parser.transformer($fake-in.Supply).schedule-on($*SCHEDULER).tap: -> $message {
    die "Did not parse as a WebSocket message" unless $message ~~ Cro::WebSocket::Message;
    $complete.keep if ++⚛$i == $messages;
}
start {
    for @tests { $fake-in.emit($_) }
    $fake-in.done;
}
await $complete;

my $t1 = now;
my $delta = $t1 - $t0;

printf "FRAMES:    %6d in %.3fs = %.3fms ave\n",
       +@tests,   $delta, 1000 * $delta / @tests;
printf "MESSAGES:  %6d in %.3fs = %.3fms ave\n",
       $messages, $delta, 1000 * $delta / $messages;
