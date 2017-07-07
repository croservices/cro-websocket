use Cro;
use Cro::HTTP::Server;
use Cro::HTTP::Router;
use Cro::HTTP::Router::WebSocket;

my $p = Promise.new;

my $app = route {
    get -> 'chat' {
        web-socket -> $incoming {
            supply {
                whenever $incoming -> $message {
                    emit(await $message.body-text);
                    $p.keep();
                }
            }
        }
    }
}

my $http-server = Cro::HTTP::Server.new(port => 3005,
                                        application => $app);

$http-server.start();

await Promise.anyof($p, Promise.in(10));

$http-server.stop();
