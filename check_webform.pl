#!/usr/bin/perl
# nagios: -epn
use Getopt::Long;
use WWW::Mechanize;
use HTTP::Cookies;
use Encode qw(decode decode_utf8);
use utf8;

# Default values
my $timeout = 15;
my $warning = 5;
my $critical = 8;
my @status = ("OK", "WARNING", "CRITICAL", "UNKNOWN");
#my $formurl = 'http://www.example.com/search';
#my $formname = "form";
#my $formfield = "search";
#my $formsubmit = "submit";
#my $verify = "some text";

sub usage { "Usage: $0 --form-url <URL> --keywords <KEYW1> ... <KEYWN> \
\t--form-name <ARG1> --form-field <ARG2> --form-submit <ARG3> --verify <ARG4>\
Nagios check, measuring response time of a web form.
\
Parameters:\
  --form-url\tThe URL of the web form. Mandatory argument\
  --form-name\tName of the form\
  --form-field\tName of the field that will be used\
  --form-submit\tValue of the submit button\
  --keywords\tFollowed by one or multiple keywords. Script will fill the web form with one of these values\
  --verify\tThe text will be used to verify the returned result.
  --timeout\tNumber of seconds after which script ends with timeout error. Default value is 15\
  --warning\tIf response time is higher than this value then check returns a Warning status. Default value is 5\
  --critical\tIf response time is higher than this value then check returns a Critical status. Default value is 8\
  --help\tDisplay this help and exit." }

# Get command line arguments
GetOptions (
    'timeout=i'      => \$timeout,
    'warning=i'      => \$warning,
    'critical=i'     => \$critical,
    'form-url=s'     => \$formurl,
    'keywords=s{,}'  => \@keywords,
    'verify=s'       => \$verify,
    'form-name=s'    => \$formname,
    'form-field=s'   => \$formfield,
    'form-submit=s'  => \$formsubmit,
    'help!'          => \$help,
) or die("Error in command line arguments. Use --help for more information\n");

if ($help) {
    die usage();
}

# Exit if --formurl is not defined
if (!$formurl) {
    print("Argument --form-url is mandatory. Use --help for more information\n");
    exit(0);
}

# Exit if mandatory arguments are missing
if (!$formname or !$formfield or !$formsubmit or !$verify) {
    print("Missing arguments. Use --help for more information\n");
    exit(0);
}

# Default keyword values
if (!@keywords) {
    my @keywords = ("keyword1", "keyword2", "keyword3", "keyword4");
}

my $start = time();
my $keyword = $keywords[int(rand(@keywords))];

# Die after $timeout seconds
$SIG{'ALRM'} = sub {
    print("WARNING! Plugin timeout, exceeded the $timeout seconds.");
    exit(1)};

alarm($timeout);

my $cookie_jar = HTTP::Cookies->new(file => "cookie-$formurl", autosave=>1, ignore_discard => 1);
$cookie_jar->clear;
my $agent = WWW::Mechanize->new(cookie_jar => $cookie_jar, autocheck => 0);
$agent->ssl_opts(SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE);

$agent->timeout($critical);
$agent->get($formurl);
$agent->form_name($formname);
$agent->field($formfield, $keyword);
$agent->click_button(value => $formsubmit);

my $exitcode;
if (defined $agent->find_link(text => $verify)) {
    if ($runtime > $critical) {
        $exitcode = 2;
    }
    elsif ($runtime > $warning) {
        $exitcode = 1;
    }
    elsif ($runtime < $warning) {
        $exitcode = 0;
    }
}
else {
    print "UNKNOWN! Keyword $keyword not found.";
    exit(3);
}

my $end = time();
my $runtime = $end - $start;

my $output = sprintf("%s - %.3f seconds | time=%.3f;%d;%d;0", $status[$exitcode], $runtime, $runtime, $warning, $critical);
print $output;
exit($exitcode);
