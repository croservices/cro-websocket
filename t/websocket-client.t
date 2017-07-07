use Cro::HTTP::Client;
use Cro::WebSocket::Client;
use Test;

my $connection = await Cro::WebSocket::Client.connect: 'http://localhost:8080/';

$connection.messages.tap(-> $mess {
                                say "Received: {await $mess.body-text}";
                            });

$connection.send('Hello');

done-testing;
