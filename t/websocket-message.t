use Cro::WebSocket::Message;
use Test;

my $message = Cro::WebSocket::Message.new('Meteor');
is $message.is-text, True, 'Is text';
is $message.is-data, True, 'Is data';
is await($message.body-text), 'Meteor', 'Body is passed';

$message = Cro::WebSocket::Message.new(Buf.new('Meteor'.encode('utf-8')));
is $message.is-binary, True, 'Is binary';
is $message.is-data, True, 'Is data';
throws-like { await($message.body-text) }, X::Cro::BodyNotText,
    'Binary message cannot have body-text called on it';
is await($message.body-blob), 'Meteor'.encode('utf-8'), 'Body can be get as blob';

my $supplier = Supplier.new;
my $supply = $supplier.Supply;
$message = Cro::WebSocket::Message.new($supply);
my Int $counter = 0;
$message.body-byte-stream.tap(-> $value { is $value, $counter, "Checked $counter"; $counter++; });
$supplier.emit(0);
$supplier.emit(1);
$supplier.emit(2);

done-testing;
