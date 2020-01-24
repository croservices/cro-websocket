use Crypt::Random;

my $mask-buf = crypt_random_buf(4);
my $masked   = crypt_random_buf(65536);
my $repeat   = @*ARGS[0] // 100;

my $t0 = now;

for ^$repeat {
    my $payload = Blob.new((@($masked) Z+^ ((@$mask-buf xx *).flat)).Array);
    # say $payload;
}

my $t1 = now;

for ^$repeat {
    # my $payload = Blob.new((@($masked) Z+^ ((@$mask-buf xx *).flat)).Array);
    # my $payload = Blob.new(@$masked >>+^>> @$mask-buf);
    my $expanded = Blob.allocate($masked.elems, $mask-buf);
    my $payload  = Blob.new($masked ~^ $expanded);
    # say $payload;
}

my $t2 = now;


printf "BASE: %6d in %.3fs = %.3fms ave\n",
       $repeat,  $t1 - $t0, 1000 * ($t1 - $t0) / $repeat;
printf "NEW:  %6d in %.3fs = %.3fms ave\n",
       $repeat,  $t2 - $t1, 1000 * ($t2 - $t1) / $repeat;
