use Cro::HTTP::Client;
use Cro::HTTP::Router::WebSocket;
use Cro::HTTP::Router;
use Cro::HTTP::Server;
use Cro::WebSocket::BodyParsers;
use Cro::WebSocket::BodySerializers;
use Cro::WebSocket::Client;
use Test;

my $app = route {
    get -> 'chat' {
        web-socket -> $incoming {
            supply {
                whenever $incoming -> $message {
                    emit('You said: ' ~ await $message.body-text);
                }
            }
        }
    }

    get -> 'parser-serializer' {
        web-socket
            :body-parsers(Cro::WebSocket::BodyParser::JSON),
            :body-serializers(Cro::WebSocket::BodySerializer::JSON),
            -> $incoming {
                supply whenever $incoming -> $message {
                    my $body = await $message.body;
                    $body<added> = 42;
                    $body<updated>++;
                    emit $body;
                }
            }
    }

    get -> 'json' {
        web-socket :json, -> $incoming {
            supply whenever $incoming -> $message {
                my $body = await $message.body;
                $body<added> = 4242;
                $body<updated>++;
                emit $body;
            }
        }
    }
}

my $http-server = Cro::HTTP::Server.new(port => 3006, application => $app);
$http-server.start();
END $http-server.stop();

throws-like { await Cro::HTTP::Client.get('http://localhost:3006/chat') },
    X::Cro::HTTP::Error::Client, 'Connection is not upgraded, 400 Bad Request';

{
    my $c = await Cro::WebSocket::Client.connect: 'http://localhost:3006/chat';

    my $p = Promise.new;
    my %seen;
    $c.messages.tap:
        -> $m {
            %seen{await $m.body-text}++;
            $p.keep if %seen == 3;
        },
        quit => {
            .note;
            exit(1);
        };

    $c.send('Hello');
    $c.send('Good');
    $c.send('Wow');

    await Promise.anyof(Promise.in(5), $p);
    ok $p.status == Kept, 'All expected responses were received';
    ok %seen{'You said: Hello'}:exists, 'Got first message response';
    ok %seen{'You said: Good'}:exists, 'Got second message response';
    ok %seen{'You said: Wow'}:exists, 'Got third message response';

    $c.close;
}

{
    use JSON::Fast;

    my $c = await Cro::WebSocket::Client.connect: 'http://localhost:3006/parser-serializer';
    my $reply-promise = $c.messages.head.Promise;
    $c.send(to-json({ updated => 99, kept => 'xxx' }));
    my $reply = await $reply-promise;
    my $parsed;
    lives-ok { $parsed = from-json await $reply.body-text },
        'Get back valid JSON from websocket endpoint with JSON parser/serializer endpoint';
    is $parsed<updated>, 100, 'Expected data returned (1)';
    is $parsed<kept>, 'xxx', 'Expected data returned (2)';
    is $parsed<added>, 42, 'Expected data returned (3)';
    $c.close;
}

{
    use JSON::Fast;

    my $c = await Cro::WebSocket::Client.connect: 'http://localhost:3006/json';
    my $reply-promise = $c.messages.head.Promise;
    $c.send(to-json({ updated => 102, kept => 'xxxy' }));
    my $reply = await $reply-promise;
    my $parsed;
    lives-ok { $parsed = from-json await $reply.body-text },
        'Get back valid JSON from websocket endpoint that uses :json';
    is $parsed<updated>, 103, 'Expected data returned (1)';
    is $parsed<kept>, 'xxxy', 'Expected data returned (2)';
    is $parsed<added>, 4242, 'Expected data returned (3)';
    $c.close;
}

done-testing;
