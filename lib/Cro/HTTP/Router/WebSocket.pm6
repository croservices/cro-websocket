use Base64;
use Digest::SHA1::Native;
use Cro::HTTP::Router;
use Cro::TCP;
use Cro::WebSocket::FrameParser;
use Cro::WebSocket::FrameSerializer;
use Cro::WebSocket::Handler;
use Cro::WebSocket::Internal;
use Cro::WebSocket::MessageParser;
use Cro::WebSocket::MessageSerializer;

sub web-socket(&handler, :$json, :$body-parsers is copy,  :$body-serializers is copy) is export {
    my constant $magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

    my $request = request;
    my $response = response;

    # Bad request checking
    if !($request.method eq 'GET')
    || !($request.http-version eq '1.1')
    || !$request.has-header('host')
    || !(($request.header('Connection') // '').lc ~~ /upgrade/)
    || decode-base64($request.header('sec-websocket-key') // '', :bin).elems != 16 {
        bad-request;
        return;
    };

    unless ($request.header('sec-websocket-version') // '') eq '13' {
        $response.status = 426;
        $response.append-header('Sec-WebSocket-Version', '13');
        return;
    };

    if $json {
        if $body-parsers === Any {
            $body-parsers = Cro::WebSocket::BodyParser::JSON;
        }
        else {
            die "Cannot use :json together with :body-parsers";
        }
        if $body-serializers === Any {
            $body-serializers = Cro::WebSocket::BodySerializer::JSON;
        }
        else {
            die "Cannot use :json together with :body-serializers";
        }
    }

    my @before;
    unless $body-parsers === Any {
        push @before, SetBodyParsers.new(:$body-parsers);
    }
    my @after;
    unless $body-serializers === Any {
        unshift @after, SetBodySerializers.new(:$body-serializers);
    }

    my $key = $request.header('sec-websocket-key');

    $response.status = 101;
    $response.append-header('Upgrade', 'websocket');
    $response.append-header('Connection', 'Upgrade');
    $response.append-header('Sec-WebSocket-Accept', encode-base64(sha1($key ~ $magic), :str));

    my Cro::Transform $pipeline = Cro.compose(
        label => "WebSocket Handler",
        Cro::WebSocket::FrameParser.new(:mask-required),
        Cro::WebSocket::MessageParser.new,
        |@before,
        Cro::WebSocket::Handler.new(&handler),
        |@after,
        Cro::WebSocket::MessageSerializer.new,
        Cro::WebSocket::FrameSerializer.new(:!mask)
    );
    $response.set-body-byte-stream:
        $pipeline.transformer(
            $request.body-byte-stream.map(-> $data { Cro::TCP::Message.new(:$data) })
        ).map({ $_.data });
}
