use Cro::WebSocket::MessageSerializer;
use Test;

sub message-to-frames($message, $count, $desc, *@checks) {
    my $serializer = Cro::WebSocket::MessageSerializer.new;
    my $fake-in = Supplier.new;
    my $completion = Promise.new;
    my Int $frame-count = 0;
    $serializer.transformer($fake-in.Supply).tap: -> $frame {
        for @checks[$frame-count].kv -> $i, $check {
            ok $check($frame), "check {$i+1}";
        }
        $frame-count++;
        $completion.keep if $count == $frame-count;
    }
    start { $fake-in.emit: $message; };
    await Promise.anyof($completion, Promise.in(5));
    if $completion {
        pass $desc;
    } else {
        flunk $desc;
    }
}

message-to-frames Cro::WebSocket::Message.new('Hello'),
                  1, 'Hello',
                  [(*.fin == True,
                    *.opcode == Cro::WebSocket::Frame::Text,
                    *.payload.decode eq 'Hello'),];

message-to-frames Cro::WebSocket::Message.new(supply {
                                                     emit 'Hel'.encode;
                                                     emit 'lo'.encode;
                                                     done;
                                                 }),
                  3, 'Splitted hello',
                  [(*.fin == False,
                    *.opcode == Cro::WebSocket::Frame::Binary,
                    *.payload.decode eq 'Hel'),
                   (*.fin == False,
                    *.opcode == Cro::WebSocket::Frame::Continuation,
                    *.payload.decode eq 'lo'),
                   (*.fin == True,
                    *.opcode == Cro::WebSocket::Frame::Continuation,
                    *.payload.decode eq '')];

done-testing;
