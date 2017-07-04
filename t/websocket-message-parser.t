use Cro::WebSocket::MessageParser;
use Test;

sub frame-to-message(@frames, $desc, *@checks) {
    my $parser = Cro::WebSocket::MessageParser.new;
    my $fake-in = Supplier.new;
    my $complete = Promise.new;
    $parser.transformer($fake-in.Supply).schedule-on($*SCHEDULER).tap: -> $message {
        pass $desc;
        for @checks.kv -> $i, $check {
            ok $check($message), "check {$i + 1}";
        }
        $complete.keep;
    }
    start {
        for @frames {
            $fake-in.emit($_);
        }
        $fake-in.done;
    }
    await Promise.anyof($complete, Promise.in(5));
    unless $complete {
        flunk $desc;
    }
}

frame-to-message (Cro::WebSocket::Frame.new(fin => True,
                                            opcode => Cro::WebSocket::Frame::Text,
                                            payload => Blob.new('Hello'.encode)),),
                 'Hello',
                 *.opcode == Cro::WebSocket::Message::Text,
                 *.fragmented == False,
                 *.body-text.result eq 'Hello';

frame-to-message (Cro::WebSocket::Frame.new(fin => False,
                                            opcode => Cro::WebSocket::Frame::Text,
                                            payload => Blob.new('Hel'.encode)),
                  Cro::WebSocket::Frame.new(fin => True,
                                            opcode => Cro::WebSocket::Frame::Continuation,
                                            payload => Blob.new('lo'.encode))),
                 'Splitted Hello',
                 *.opcode == Cro::WebSocket::Message::Text,
                 *.fragmented == True,
                 *.body-text.result eq 'Hello';

frame-to-message (Cro::WebSocket::Frame.new(fin => True,
                                            opcode => Cro::WebSocket::Frame::Ping,
                                            payload => Blob.new('Hello'.encode)),),
                 'Unmasked ping request',
                 *.opcode == Cro::WebSocket::Message::Ping,
                 *.fragmented == False,
                 *.body-text.result eq 'Hello';

my @random-data = 255.rand.Int xx 256;

frame-to-message (Cro::WebSocket::Frame.new(fin => False,
                                            opcode => Cro::WebSocket::Frame::Binary,
                                            payload => Blob.new(@random-data[0..75])),
                  Cro::WebSocket::Frame.new(fin => False,
                                            opcode => Cro::WebSocket::Frame::Continuation,
                                            payload => Blob.new(@random-data[75^..^173])),
                  Cro::WebSocket::Frame.new(fin => True,
                                            opcode => Cro::WebSocket::Frame::Continuation,
                                            payload => Blob.new(@random-data[173..*])),),
                 'Splitted big data package',
                 *.opcode == Cro::WebSocket::Message::Binary,
                 *.fragmented == True,
                 *.body-blob.result == Blob.new(@random-data);

done-testing;
