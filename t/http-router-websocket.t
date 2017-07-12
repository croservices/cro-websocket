use Cro::WebSocket::Client;
use Cro::HTTP::Server;
use Cro::HTTP::Router;
use Cro::HTTP::Router::WebSocket;
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
}

my $http-server = Cro::HTTP::Server.new(port => 3005,
                                        application => $app);

$http-server.start();

my $c = await Cro::WebSocket::Client.connect: 'http://localhost:3005/chat';

my $count = 0;
my $p = Promise.new;

$c.messages.tap(
    -> $m {
        $count++;
        $p.keep if $count == 3;
    }
);

# XXX Remove awaits after race hang will be fixed
$c.send('Hello');
await Promise.in(1);
$c.send('Good');
await Promise.in(1);
$c.send('Wow');

await $p;

$http-server.stop();

done-testing;
