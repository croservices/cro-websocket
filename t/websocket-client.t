use Cro::WebSocket::BodyParsers;
use Cro::WebSocket::BodySerializers;
use Cro::WebSocket::Client;
use Cro::HTTP::Server;
use Cro::HTTP::Router;
use Cro::HTTP::Router::WebSocket;
use JSON::Fast;
use Test;

my $done = Promise.new;

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
    get -> 'done' {
        web-socket -> $incoming, $close {
            supply {
                whenever $incoming {
                    done;
                }
            }
        }
    }
    get -> 'json' {
        web-socket -> $incoming {
            supply whenever $incoming {
                my $json = from-json await .body-text;
                $json<added> = 42;
                $json<updated>++;
                emit to-json $json;
            }
        }
    }
    get -> 'plain' {
        content 'text/plain', 'Hello';
    }
}

my $http-server = Cro::HTTP::Server.new(port => 3005, application => $app);
$http-server.start();
END { $http-server.stop() };


# Non-Websocket route testing
{
    throws-like {
        Cro::WebSocket::Client.connect('http://localhost:3005/plain').result;
    }, X::Cro::WebSocket::Client::CannotUpgrade, 'Cannot connect to non-websocket route';
}

# Done testing
{
    my $connection = Cro::WebSocket::Client.connect: 'http://localhost:3005/done';

    await Promise.anyof($connection, Promise.in(5));
    if $connection.status != Kept {
        flunk 'Connection promise is not Kept';
        if $connection.status == Broken {
            diag $connection.cause;
        }
        bail-out;
    } else {
        $connection = $connection.result;
    }

    $connection.send('Foo');

    # We need to wait until Handler's Close met the Connection
    await $connection.messages;

    dies-ok { $connection.send('Bar') }, 'Cannot send anything to closed channel(by done)';
}

# Ping testing
{
    my $connection = Cro::WebSocket::Client.connect: 'http://localhost:3005/chat';

    await Promise.anyof($connection, Promise.in(5));
    die "Connection timed out" unless $connection;

    $connection .= result;

    my $ping = $connection.ping;
    await Promise.anyof($ping, Promise.in(5));
    ok $ping.status ~~ Kept, 'Empty ping is recieved';

    $ping = $connection.ping('First');
    await Promise.anyof($ping, Promise.in(5));
    ok $ping.status ~~ Kept, 'Ping is recieved';

    $ping = $connection.ping(:0timeout);
    dies-ok { await $ping }, 'Timeout breaks ping promise';
}

# Chat testing
{
    my $connection = Cro::WebSocket::Client.connect: 'http://localhost:3005/chat';

    await Promise.anyof($connection, Promise.in(5));
    die "Connection timed out" unless $connection;

    $connection .= result;

    my $p = Promise.new;
    $connection.messages.tap(-> $mess {
                                    ok (await $mess.body-text).starts-with('You said:');
                                    $p.keep;
                                });

    $connection.send('Hello');

    await Promise.anyof($p, Promise.in(5));

    unless $p.status ~~ Kept {
        flunk "send does not work";
    }

    # Closing
    my $closed = $connection.close;
    await Promise.anyof($closed, Promise.in(1));
    ok $closed.status ~~ Kept, 'The connection is closed by close() call';

    dies-ok { $connection.send('Bar') }, 'Cannot send anything to closed channel by close() call';
}

# Body parsers/serializers
{
    my $client = Cro::WebSocket::Client.new:
        body-parsers => Cro::WebSocket::BodyParser::JSON,
        body-serializers => Cro::WebSocket::BodySerializer::JSON;
    my $connection = await $client.connect: 'http://localhost:3005/json';
    my $response = $connection.messages.head.Promise;
    lives-ok { $connection.send({ kept => 'xxx', updated => 99 }) },
        'Can send Hash using client with JSON body serializer installed';
    given await $response {
        my $body = await .body;
        ok $body.isa(Hash), 'Got hash back from body, thanks to JSON body parser';
        is $body<kept>, 'xxx', 'Correct hash content (1)';
        is $body<added>, 42, 'Correct hash content (2)';
        is $body<updated>, 100, 'Correct hash content (3)';
    }
}

# The :json option for the client
{
    my $client = Cro::WebSocket::Client.new: :json;
    my $connection = await $client.connect: 'http://localhost:3005/json';
    my $response = $connection.messages.head.Promise;
    lives-ok { $connection.send({ kept => 'xxy', updated => 999 }) },
        'Can send Hash using client constructed with :json';
    given await $response {
        my $body = await .body;
        ok $body.isa(Hash), 'Got hash back from body, thanks to :json';
        is $body<kept>, 'xxy', 'Correct hash content (1)';
        is $body<added>, 42, 'Correct hash content (2)';
        is $body<updated>, 1000, 'Correct hash content (3)';
    }
}

done-testing;
