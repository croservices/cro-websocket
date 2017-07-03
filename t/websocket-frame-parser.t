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

sub test-example($buf, $mask-required, $desc, *@checks) {
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
        $fake-in.emit(Cro::TCP::Message.new(data => $buf));
        $fake-in.done;
    }
    await Promise.anyof($complete, Promise.in(5));
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

done-testing;
