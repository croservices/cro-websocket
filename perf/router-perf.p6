use Cro::HTTP::Client;
use Cro::HTTP::Router::WebSocket;
use Cro::HTTP::Router;
use Cro::HTTP::Server;
use Cro::WebSocket::BodyParsers;
use Cro::WebSocket::BodySerializers;
use Cro::WebSocket::Client;
use JSON::Fast;

my $application = route {
    get -> 'chat' {
        web-socket -> $incoming {
            supply {
                whenever $incoming -> $message {
                    emit('You said: ' ~ await $message.body-text);
                }
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

my $port = 3006;
my $http-server = Cro::HTTP::Server.new(:$port, :$application);
$http-server.start;
END $http-server.stop;

my $repeat         = @*ARGS[0] // 1;
my $json           = to-json({ updated => 99, kept => 'xxx' });
my $plain-client   = await Cro::WebSocket::Client.connect: "http://localhost:$port/chat";
my $json-client    = await Cro::WebSocket::Client.connect: "http://localhost:$port/json";
my $plain-complete = Promise.new;
my $json-complete  = Promise.new;
my atomicint $i    = 0;
my atomicint $j    = 0;

my $t0 = now;

$plain-client.messages.tap: -> $message {
    my $text = await $message.body-text;
    $plain-complete.keep if ++⚛$i == $repeat;
}
start {
    $plain-client.send('Hello') for ^$repeat;
}
await $plain-complete;

my $t1 = now;

$json-client.messages.tap: -> $message {
    say 1;
    my $promise = $message.body-text;
    say 2;
    my $json = await $promise;
    say 3;
    $json-complete.keep if ++⚛$j == $repeat;
}
start {
    $json-client.send($json) for ^$repeat;
}
await $json-complete;

my $t2 = now;

$plain-client.close;
$json-client.close;

printf "PLAIN: %6d in %.3fs = %.3fms ave\n",
       $repeat, $t1 - $t0, 1000 * ($t1 - $t0) / $repeat;
printf "JSON:  %6d in %.3fs = %.3fms ave\n",
       $repeat, $t2 - $t1, 1000 * ($t2 - $t1) / $repeat;
