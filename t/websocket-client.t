use Cro::WebSocket::Client;
use Cro::HTTP::Server;
use Cro::HTTP::Router;
use Cro::HTTP::Router::WebSocket;
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
}

my $http-server = Cro::HTTP::Server.new(port => 3005, application => $app);
$http-server.start();
END { $http-server.stop() };

# Done testing

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

# Ping testing

$connection = Cro::WebSocket::Client.connect: 'http://localhost:3005/chat';

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

# Chat testing

$connection = Cro::WebSocket::Client.connect: 'http://localhost:3005/chat';

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

done-testing;
