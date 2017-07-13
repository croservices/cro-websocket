use Cro::TCP;
use Cro::WebSocket::FrameParser;
use Cro::WebSocket::Frame;
use Test;

ok Cro::WebSocket::FrameParser ~~ Cro::Transform,
    'WebSocket frame parser is a transform';
ok Cro::WebSocket::FrameParser.consumes === Cro::TCP::Message,
    'WebSocket frame parser consumes TCP messages';
ok Cro::WebSocket::FrameParser.produces === Cro::WebSocket::Frame,
    'WebSocket frame parser produces Frames';

sub test-example($buf, $mask-required, $desc, *@checks, :$split = False) {
    my $parser = Cro::WebSocket::FrameParser.new(:$mask-required);
    my $fake-in = Supplier.new;
    my $complete = Promise.new;
    $parser.transformer($fake-in.Supply).schedule-on($*SCHEDULER).tap: -> $frame {
        ok $frame ~~ Cro::WebSocket::Frame, $desc;
        for @checks.kv -> $i, $check {
            ok $check($frame), "check {$i + 1}";
        }
        $complete.keep;
    }
    start {
        if $split {
            my Int $split = $buf.elems.rand.Int;
            my $buf1 = $buf.subbuf(0, $split) ;
            my $buf2 = $buf.subbuf($split);
            $fake-in.emit(Cro::TCP::Message.new(data => $buf1));
            $fake-in.emit(Cro::TCP::Message.new(data => $buf2));
        } else {
            $fake-in.emit(Cro::TCP::Message.new(data => $buf));
        }
        $fake-in.done;
    }
    await Promise.anyof($complete, Promise.in(5));
    unless $complete {
        flunk $desc;
    }
}

test-example Buf.new([0x81, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f]),
             False, 'Hello',
             *.fin == True,
             *.opcode == Cro::WebSocket::Frame::Text,
             *.payload.decode eq 'Hello';

test-example Buf.new([0x81, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58]),
             True,  'Masked Hello',
             *.fin == True,
             *.opcode == Cro::WebSocket::Frame::Text,
             *.payload.decode eq 'Hello';

test-example Buf.new([0x01, 0x03, 0x48, 0x65, 0x6c]),
             False, 'Hel',
             *.fin == False,
             *.opcode == Cro::WebSocket::Frame::Text,
             *.payload.decode eq 'Hel';

test-example Buf.new([0x80, 0x02, 0x6c, 0x6f]),
             False, 'lo',
             *.fin == True,
             *.opcode == Cro::WebSocket::Frame::Continuation,
             *.payload.decode eq 'lo';

test-example Buf.new([0x89, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f]),
             False, 'Unmasked ping request',
             *.fin == True,
             *.opcode == Cro::WebSocket::Frame::Ping,
             *.payload.decode eq 'Hello';

test-example Buf.new([0x8a, 0x00]),
             False, 'Empty unmasked ping response',
             *.fin == True,
             *.opcode == Cro::WebSocket::Frame::Pong,
             *.payload.decode eq '';

test-example Buf.new([0x8a, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58]),
             True, 'Masked ping response',
             *.fin == True,
             *.opcode == Cro::WebSocket::Frame::Pong,
             *.payload.decode eq 'Hello';

test-example Buf.new([0x8a, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58]),
             True, 'Masked ping response',
             *.fin == True,
             *.opcode == Cro::WebSocket::Frame::Pong,
             *.payload.decode eq 'Hello',
             split => True;

my @random-data = 255.rand.Int xx 256;
my $message = Buf.new([0x82, 0x7E, 0x01, 0x00, |@random-data]);

test-example $message,
             False, '256 bytes binary message in a single unmasked frame',
             *.fin == True,
             *.opcode == Cro::WebSocket::Frame::Binary,
             *.payload == @random-data;

test-example $message,
             False, '256 bytes binary message in a single unmasked frame',
             *.fin == True,
             *.opcode == Cro::WebSocket::Frame::Binary,
             *.payload == @random-data,
             split => True;

@random-data = 255.rand.Int xx 65536;
$message = Buf.new([0x82, 0x7F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, |@random-data]);

test-example $message,
             False, '64 KiB binary message in a single unmasked frame',
             *.fin == True,
             *.opcode == Cro::WebSocket::Frame::Binary;

test-example $message,
             False, '64 KiB binary message in a single unmasked frame',
             *.fin == True,
             *.opcode == Cro::WebSocket::Frame::Binary,
             split => True;

done-testing;
