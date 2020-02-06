use Cro::TCP;
use Cro::WebSocket::FrameParser;
use Cro::WebSocket::Frame;


sub make-tcp(@data) {
    Cro::TCP::Message.new(data => Buf.new(@data))
}

my @buffers-clear =
    [0x81, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f],
    [0x01, 0x03, 0x48, 0x65, 0x6c],
    [0x80, 0x02, 0x6c, 0x6f],
    [0x89, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f],
    [0x8a, 0x00],
;

my @buffers-masked =
    [0x81, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58],
    [0x8a, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58],
;

my @random-data = 255.rand.Int xx 256;
@buffers-clear.push:  [0x82, 0x7E, 0x01, 0x00, |@random-data];
@buffers-masked.push: [0x82, 0xFE, 0x01, 0x00, 0x37, 0xfa, 0x21, 0x3d, |@random-data];

@random-data = 255.rand.Int xx 32768;
@buffers-clear.push:  [0x82, 0x7E, 0x80, 0x00, |@random-data];
@buffers-masked.push: [0x82, 0xFE, 0x80, 0x00, 0x37, 0xfa, 0x21, 0x3d, |@random-data];

@random-data = 255.rand.Int xx 65536;
@buffers-clear.push:  [0x82, 0x7F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, |@random-data];
@buffers-masked.push: [0x82, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x37, 0xfa, 0x21, 0x3d, |@random-data];


my $repeat          = @*ARGS[0] // 1_000;
my @tests-clear     = @buffers-clear.map:  -> $bytes { |(make-tcp($bytes) for ^$repeat) };
my @tests-masked    = @buffers-masked.map: -> $bytes { |(make-tcp($bytes) for ^$repeat) };
my $parser-clear    = Cro::WebSocket::FrameParser.new(:!mask-required);
my $parser-masked   = Cro::WebSocket::FrameParser.new( :mask-required);
my $clear-in        = Supplier.new;
my $masked-in       = Supplier.new;
my $clear-complete  = Promise.new;
my $masked-complete = Promise.new;
my atomicint $i     = 0;
my atomicint $j     = 0;

my $t0 = now;

$parser-clear.transformer($clear-in.Supply).schedule-on($*SCHEDULER).tap: -> $frame {
    die "Did not parse as a WebSocket frame" unless $frame ~~ Cro::WebSocket::Frame;
    $clear-complete.keep if ++⚛$i == @tests-clear;
}
start {
    for @tests-clear { $clear-in.emit($_) }
    $clear-in.done;
}
await $clear-complete;

my $t1 = now;

$parser-masked.transformer($masked-in.Supply).schedule-on($*SCHEDULER).tap: -> $frame {
    die "Did not parse as a WebSocket frame" unless $frame ~~ Cro::WebSocket::Frame;
    $masked-complete.keep if ++⚛$j == @tests-masked;
}
start {
    for @tests-masked { $masked-in.emit($_) }
    $masked-in.done;
}
await $masked-complete;

my $t2 = now;

printf "CLEAR:  %6d in %.3fs = %.3fms ave\n",
       +@tests-clear,  $t1 - $t0, 1000 * ($t1 - $t0) / @tests-clear;
printf "MASKED: %6d in %.3fs = %.3fms ave\n",
       +@tests-masked, $t2 - $t1, 1000 * ($t2 - $t1) / @tests-masked;
