use Cro::WebSocket::MessageSerializer;
use Test;

sub message-to-frames(@messages, $count, $desc, *@checks) {
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
    await start {
        for @messages { $fake-in.emit($_) };
        $fake-in.done;
    };
    await Promise.anyof($completion, Promise.in(5));
    if $completion {
        pass $desc;
    } else {
        flunk $desc;
    }
}

message-to-frames [Cro::WebSocket::Message.new('Hello')],
                   1, 'Hello',
                   [(*.fin == True,
                     *.opcode == Cro::WebSocket::Frame::Text,
                     *.payload.decode eq 'Hello'),];

message-to-frames [Cro::WebSocket::Message.new(supply {
                                                      emit 'Hel'.encode;
                                                      emit 'lo'.encode;
                                                      done;
                                                  })],
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

message-to-frames (Cro::WebSocket::Message.new(opcode => Cro::WebSocket::Message::Ping,
                                               fragmented => False,
                                               body-byte-stream => supply { emit 'Ping'.encode; done; }),),
                  1, 'Control message',
                  [(*.fin == True,
                    *.opcode == Cro::WebSocket::Frame::Ping,
                    *.payload.decode eq 'Ping')];

my $p1 = Promise.new;
my $p2 = Promise.new;

my $s = Supplier::Preserving.new;

start {
    $s.emit: 'Before'.encode;
    $p1.keep;
    await $p2;
    $s.emit: 'After'.encode;
    $s.done;
};

message-to-frames (Cro::WebSocket::Message.new($s.Supply),
                   Cro::WebSocket::Message.new(opcode => Cro::WebSocket::Message::Ping,
                                               fragmented => False,
                                               body-byte-stream => supply { await $p1; emit 'Ping'.encode; $p2.keep; done; }),
                  ),
                  4, 'Control message in-between',
                  [(*.fin == False,
                    *.opcode == Cro::WebSocket::Frame::Binary,
                    *.payload.decode eq 'Before'),
                   (*.fin == True,
                    *.opcode == Cro::WebSocket::Frame::Ping,
                    *.payload.decode eq 'Ping'),
                   (*.fin == False,
                    *.opcode == Cro::WebSocket::Frame::Continuation,
                    *.payload.decode eq 'After'),
                   (*.fin == True,
                    *.opcode == Cro::WebSocket::Frame::Continuation,
                    *.payload.decode eq '')];

done-testing;
