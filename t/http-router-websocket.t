use Cro::HTTP::Client;
use Cro::HTTP::Router::WebSocket;
use Cro::HTTP::Router;
use Cro::HTTP::Server;
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
}

my $http-server = Cro::HTTP::Server.new(port => 3005,
                                        application => $app);

$http-server.start();

throws-like { await Cro::HTTP::Client.get('http://localhost:3005/chat') },
    X::Cro::HTTP::Error::Client, 'Connection is not upgraded, 400 Bad Request';

my $c = await Cro::WebSocket::Client.connect: 'http://localhost:3005/chat';

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

$http-server.stop();

done-testing;
