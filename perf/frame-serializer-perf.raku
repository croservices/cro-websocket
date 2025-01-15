use Cro::TCP;
use Cro::WebSocket::FrameSerializer;
use Cro::WebSocket::Frame;

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
\(Text, 'Hello', True),
\(Text, 'Hel'),
\(Cont, 'lo'),
\(Ping, 'Hello'),
\(Pong, 'Hello'),
\(Binary, @random-data[^256],   True),
\(Binary, @random-data[^32768], True),
\(Binary, @random-data,         True),
;

my $repeat          = @*ARGS[0] // 1_000;
my @tests           = @frames.map: -> $c { |( make-frame(|$c) for ^$repeat) };
my $serial-clear    = Cro::WebSocket::FrameSerializer.new(:!mask);
my $serial-masked   = Cro::WebSocket::FrameSerializer.new( :mask);
my $clear-in        = Supplier.new;
my $masked-in       = Supplier.new;
my $clear-complete  = Promise.new;
my $masked-complete = Promise.new;
my atomicint $i     = 0;
my atomicint $j     = 0;

my $t0 = now;

$serial-clear.transformer($clear-in.Supply).schedule-on($*SCHEDULER).tap: -> $message {
    die "Did not serialize as a TCP message" unless $message ~~ Cro::TCP::Message;
    $clear-complete.keep if ++⚛$i == @tests;
}
start {
    for @tests { $clear-in.emit($_) }
    $clear-in.done;
}
await $clear-complete;

my $t1 = now;

$serial-masked.transformer($masked-in.Supply).schedule-on($*SCHEDULER).tap: -> $message {
    die "Did not serialize as a TCP message" unless $message ~~ Cro::TCP::Message;
    $masked-complete.keep if ++⚛$j == @tests;
}
start {
    for @tests { $masked-in.emit($_) }
    $masked-in.done;
}
await $masked-complete;

my $t2 = now;

printf "CLEAR:  %6d in %.3fs = %.3fms ave\n",
       +@tests, $t1 - $t0, 1000 * ($t1 - $t0) / @tests;
printf "MASKED: %6d in %.3fs = %.3fms ave\n",
       +@tests, $t2 - $t1, 1000 * ($t2 - $t1) / @tests;
