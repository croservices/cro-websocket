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

my $connection = await Cro::WebSocket::Client.connect: 'http://localhost:3005/chat';

my $p = Promise.new;
$connection.messages.tap(-> $mess {
                                ok (await $mess.body-text).starts-with('You said:');
                                $p.keep;
                            });

$connection.send('Hello');

await $p;

END { $http-server.stop() };

done-testing;
