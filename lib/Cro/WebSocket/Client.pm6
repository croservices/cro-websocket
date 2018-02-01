use Base64;
use Cro::HTTP::Client;
use Cro::HTTP::Header;
use Cro::Uri;
use Cro::WebSocket::BodyParsers;
use Cro::WebSocket::BodySerializers;
use Cro::WebSocket::Client::Connection;
use Crypt::Random;
use Digest::SHA1::Native;

class Cro::WebSocket::Client {
    has $.uri;
    has $.body-serializers;
    has $.body-parsers;

    submethod BUILD(:$!uri, :$body-serializers, :$body-parsers, :$json --> Nil) {
        if $json {
            if $body-parsers === Any {
                $!body-parsers = Cro::WebSocket::BodyParser::JSON;
            }
            else {
                die "Cannot use :json together with :body-parsers";
            }
            if $body-serializers === Any {
                $!body-serializers = Cro::WebSocket::BodySerializer::JSON;
            }
            else {
                die "Cannot use :json together with :body-serializers";
            }
        }
        else {
            $!body-parsers = $body-parsers;
            $!body-serializers = $body-serializers;
        }
    }

    method connect($uri = '', :%ca? --> Promise) {
        my $parsed-url;
        if self && self.uri {
            $parsed-url = Cro::Uri.parse($uri ~~ Cro::Uri
                                         ?? self.uri ~ $uri.Str
                                         !! self.uri ~ $uri);
        } else {
            $parsed-url = $uri ~~ Cro::Uri ?? $uri !! Cro::Uri.parse($uri);
        }
        if $parsed-url.scheme eq 'wss' && !%ca {
            die "Cannot connect through wss without certificate specified";
        }

        start {
            my $out  = Supplier::Preserving.new;

            my $key = encode-base64(crypt_random_buf(16), :str);
            my $magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
            my $answer = encode-base64(sha1($key ~ $magic), :str);

            my %options = headers => (Cro::HTTP::Header.new(name => 'Upgrade', value => 'websocket'),
                Cro::HTTP::Header.new(name => 'Connection', value => 'Upgrade'),
                Cro::HTTP::Header.new(name => 'Sec-WebSocket-Version', value => '13'),
                Cro::HTTP::Header.new(name => 'Sec-WebSocket-Key', value => $key),
                Cro::HTTP::Header.new(name => 'Sec-WebSocket-Protocol', value => 'echo-protocol'));

            %options<body-byte-stream> = $out.Supply;
            my $resp = await Cro::HTTP::Client.get($parsed-url, %options, :%ca);
            if $resp.status == 101 {
                # Headers check;
                die unless $resp.header('upgrade') eq 'websocket';
                die unless $resp.header('connection') eq 'Upgrade';
                die unless $resp.header('Sec-WebSocket-Accept').trim eq $answer;
                # No extensions for now
                # die unless $resp.header('Sec-WebSocket-Extensions') eq Nil;
                # die unless $resp.header('Sec-WebSocket-Protocol') eq 'echo-protocol'; # XXX
                Cro::WebSocket::Client::Connection.new(
                    in => $resp.body-byte-stream, :$out,
                    |(%(:$!body-parsers, :$!body-serializers) with self)
                )
            } else {
                die 'Server failed to upgrade web socket connection';
            }
        }
    }
}
