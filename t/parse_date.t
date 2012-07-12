require 'magbot';
use Test::More;

sub is_date($@) {
    my ($date, $y1, $m1) = @_;
    my ($y2, $m2) = parse_date($date);
    is $y2 => $y1, "given $date year should equal $y1";
    is $m2 => $m1, "given $date month should equal $m1";
}

my @date = qw{ 2012 09 };
is_date '2012-09' => @date;
is_date '09/2012' => @date;
is_date '2012-9'  => @date;
is_date '9/2012'  => @date;

done_testing;
