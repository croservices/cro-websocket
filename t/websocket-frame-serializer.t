use Cro::TCP;
use Cro::WebSocket::FrameParser;
use Cro::WebSocket::FrameSerializer;
use Cro::WebSocket::Frame;
use Test;

ok Cro::WebSocket::FrameSerializer ~~ Cro::Transform,
    'WebSocket frame serializer is a transform';
ok Cro::WebSocket::FrameSerializer.consumes === Cro::WebSocket::Frame,
    'WebSocket frame serializer consumes TCP messages';
ok Cro::WebSocket::FrameSerializer.produces === Cro::TCP::Message,
    'WebSocket frame serializer produces Frames';

sub test-example($frame, $mask, $desc) {
    my $serializer = Cro::WebSocket::FrameSerializer.new(:$mask);
    my $parser = Cro::WebSocket::FrameParser.new(mask-required => $mask);
    my $fake-in-s = Supplier.new;
    my $fake-in-p = Supplier.new;
    my $complete = Promise.new;
    $serializer.transformer($fake-in-s.Supply).schedule-on($*SCHEDULER).tap: -> $message {
        $parser.transformer($fake-in-p.Supply).schedule-on($*SCHEDULER).tap: -> $newframe {
            is-deeply $newframe, $frame, $desc;
            $complete.keep;
        }
        $fake-in-p.emit($message);
        $fake-in-p.done;
    }
    start {
        $fake-in-s.emit($frame);
        $fake-in-s.done;
    }
    await Promise.anyof($complete, Promise.in(5));
}

test-example Cro::WebSocket::Frame.new(fin => True,
                                       opcode => Cro::WebSocket::Frame::Text,
                                       payload => Blob.new('Hello'.encode)),
             False, 'Hello text frame';

test-example Cro::WebSocket::Frame.new(fin => True,
                                       opcode => Cro::WebSocket::Frame::Text,
                                       payload => Blob.new('Hello'.encode)),
             True, 'Masked Hello';

test-example Cro::WebSocket::Frame.new(fin => False,
                                       opcode => Cro::WebSocket::Frame::Text,
                                       payload => Blob.new('Hel'.encode)),
             False, 'Hel';

test-example Cro::WebSocket::Frame.new(fin => True,
                                       opcode => Cro::WebSocket::Frame::Continuation,
                                       payload => Blob.new('lo'.encode)),
             False, 'lo';

test-example Cro::WebSocket::Frame.new(fin => True,
                                       opcode => Cro::WebSocket::Frame::Ping,
                                       payload => Blob.new('Hello'.encode)),
             False, 'Unmasked ping request';

test-example Cro::WebSocket::Frame.new(fin => True,
                                       opcode => Cro::WebSocket::Frame::Pong,
                                       payload => Blob.new('Hello'.encode)),
             True, 'Masked ping response';

my @random-data = 255.rand.Int xx 256;

test-example Cro::WebSocket::Frame.new(fin => True,
                                       opcode => Cro::WebSocket::Frame::Binary,
                                       payload => Blob.new(@random-data)),
             False, '256 bytes binary message in a single unmasked frame';

@random-data = 255.rand.Int xx 65536;

test-example Cro::WebSocket::Frame.new(fin => True,
                                       opcode => Cro::WebSocket::Frame::Binary,
                                       payload => Blob.new(@random-data)),
             False, '64 KiB binary message in a single unmasked frame';

done-testing;
