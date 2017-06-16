#!/usr/bin/perl
# nagios: -epn
# This check searches for a given set of patterns and
# returns a Warning if any of them matches in the specified log files
use strict;
use POSIX qw(strftime);
use Getopt::Std;
use Getopt::Long;
use vars qw( $timeout @pattern $patternfile $hosts $subdir $daily @skiplist $timeback $help );
use Data::Dumper;
use Time::HiRes qw/ time /;

# Print script usage
sub usage { "Usage: $0 ( --pattern <PATTERN1> | --patternfile <FILE> ) --timeout <TIMEOUT> [OPTION]\
Nagios check for searching patterns on logfiles.\
Multiple patterns can be checked on logfiles. Patterns can be defined from cli or from a text file.\
Pattern file must follow the specified form: NAME,\"PATTERN\"\
\
Usage Examples:\
$0 --pattern \"PATTERN1\" \"PATTERN2\" --timeout 30\
$0 --patternfile PATTERNFILE --timeout 30 --hosts HOST --daily\
$0 --pattern \"PATTERN\" --timeout 30 --hosts HOST1,HOST2 --timeback 2\
\
Parameters:\
--pattern\tFollowed by one or multiple patterns enclosed in double quotes.\
--patternfile\tFollowed by a file which contains patterns in the form: NAME,\"PATTERN\".\
--timeout\tNumber of seconds after which script ends with timeout error.\
          \tDefault value is 60 secs.
--hosts   \tFollowed by a HOSTNAME. If specified the script will parse the defined servers logs.\
          \tFor multiple hosts, seperate them with a comma \",\".
          \tUse \"*\" or ALL to check all hosts.
--subdir  \tShould be combined with option --hosts. Use to define a host sub directory.\
--timeback\tDefault value is 0. The script will search in past N daily or hourly logfiles.\
--daily   \tIf specified, script will search in daily logfiles, otherwise in hourly.\
--skiplist\tFollowed by multiple patterns. Those patterns will be ignored.\
          \tDefault value is \"nagios3\"\n" }

# Returns an Array of Hashes for each pattern {name, re, lineno, occurences, output}
sub processPatternfile {
    my $patternfile = shift;
    my @patterns_list = ();

    # Process patternfile
    chomp($patternfile);
    if (-e $patternfile) {
        open(FH, '<', $patternfile) || die "Cannot open file $patternfile!";
    }
    else {
        print "No file $patternfile found!";
        exit(2);
    }

    # Create an array of hashes for each pattern {name,re,lineno,occurences,output}
    my $index = 0;
    my $config_line;
    while ($config_line = <FH>) {
        chomp($config_line);
        my @config_split = split(/([^,]+),/, $config_line);  # split each line on first comma char
        my $pattern_wo_quotes = substr $config_split[2], 1, -1;  # remove double quotes from pattern
        @patterns_list[$index] = { name => $config_split[1], re => qr/($pattern_wo_quotes)/i, lineno => 0, occurences => 0, output => '',};
        $index++;
    }
    close(FH);
    return @patterns_list;
}

# Returns an array of log files in full path
sub getLogfiles {
    my $hosts = shift;
    my $daily = shift;
    my $timeback = shift;
    my $subdir = shift;
    my @logfiles = ();
    my @hosts_list = ();
    my $mydate = time();
    my $path = "/var/log/";
    my $datetype = "HOURLY.";

    if ($daily) {
        $datetype = "DAILY.";
    }

    if ($hosts) {
        if ($hosts eq "*" or $hosts eq "ALL") {
            opendir(my $parrent_dir, $path);
            while (my $dir = readdir($parrent_dir)) {
                if (-d $path . "/" . $dir) {
                    if ($dir ne "." and $dir ne "..") {
                        push @hosts_list, $dir;
                    }
                }
            }
        }
        else {
            @hosts_list = split(/,/, $hosts);
        }
    }
    else {
        push @hosts_list, '';
    }

    foreach my $host (@hosts_list) {
        my $tmppath = $path;
        my $filename = $datetype;

        if ($host) {
            $tmppath = $tmppath . $host . "/";
            $filename = $filename . $host . ".";
        }

        if ($subdir) {
            $tmppath = $tmppath . $subdir . "/";
            $filename = $filename . $subdir . ".";
        }

        for (my $i = 0; $i <= $timeback; $i++) {
            my $tmpdate;

            if ($daily) {
                $tmpdate = strftime "%Y.%m.%d", localtime($mydate - (86400 * $i));
            }
            else {
                $tmpdate = strftime "%Y.%m.%d.%H", localtime($mydate - (3600 * $i));
            }

            push @logfiles, $tmppath . $filename . $tmpdate;
        }
    }

    return @logfiles;
}

# Default params
GetOptions(
    'timeout=i'     => \$timeout,
    'pattern=s{,}'  => \@pattern,
    'patternfile=s' => \$patternfile,
    'hosts=s'       => \$hosts,
    'daily'         => \$daily,
    'subdir=s'      => \$subdir,
    'skiplist=s{,}' => \@skiplist,
    'timeback=i'    => \$timeback,
    'help!'         => \$help,
) or die usage();

# Help
if ($help) {
    die usage();
}

# Script start time
my $start_run = time();

# Script Timeout
if (!$timeout) {
    $timeout = 60;
}

$SIG{'ALRM'} = sub {
    print ("Warning. Script exceeded timeout ($timeout secs.)\n");
    exit(1)
};

# Check pattern parameters
if (@pattern && $patternfile) {
    print "Cannot use both --pattern and --patternfile options.\n";
    print "Try with --help for more information.\n";
    exit(2);
}
elsif (!@pattern && !$patternfile) {
    print "One of the --pattern and --patternfile options must be defined.\n";
    print "Try with --help for more information.\n";
    exit(2);
}

# Check subdir parameter
if ($subdir && !$hosts) {
    print "Parameter subdir should be combined with --hosts option.\n";
    exit(2)
}

# Check skiplist parameter
# If none defined, use the following
if (!@skiplist) {
    @skiplist=("nagios");
}

# Check timeback parameter
# If none define, set to 0
if (!$timeback) {
    $timeback = 0;
}

# Process patterns
my @patterns_list = ();
if (@pattern) {
    for (my $i = 0; $i < @pattern; $i++) {
        my $tmp = $i + 1;
        @patterns_list[$i] = { name => "Pattern$tmp", re => qr/($pattern[$i])/i, lineno => 0, occurences => 0, output => '',};
    }
}
else {
    @patterns_list = processPatternfile($patternfile);
}
my $patterns_size = @patterns_list;

# Set the alarm
alarm($timeout);

# Parse logfiles
my $exit_code = 0;
my $status = "OK";
my $files_number = 0;
my @logfiles = getLogfiles($hosts, $daily, $timeback, $subdir);

foreach my $logfile (@logfiles) {
    chomp($logfile);
    if (-e $logfile) {
        $files_number += 1;
        open(FH, '<', $logfile) || die "Cannot open file $logfile";

        #print "INFO: Checking logfile: $logfile\n";

        # Read logfile, line by line and check for pattern matches
        while (my $line = <FH>) {
            foreach (@patterns_list) {
                if ($line =~ $_->{re} && $_->{lineno} < 100) {
                    my $skipthis = 0;
                    foreach my $skipword (@skiplist) {
                        ($line =~ /$skipword/i) && ($skipthis = 1)
                    }
                    if ($skipthis == 0) {
                        $_->{lineno} += 1;
                        $_->{occurences} +=1;
                        $_->{output} .= ">> Warning: $line";
                        $exit_code = 1;
                    }
                }
            }
        }
        close(FH);
    }
}

# Find the number of patterns with no matches
my $patterns_ok = 0;
my $patterns_warn = "";
foreach (@patterns_list) {
    if ($_->{occurences} == 0) {
        $patterns_ok += 1;
    }
    else {
        $patterns_warn = $patterns_warn . "," . $_->{name};
    }
}
# Remove first comma
$patterns_warn =~ s/^.//;

# Execution time
my $end_run = time();
my $run_time = $end_run - $start_run;

# Output
if ($exit_code == 1 or $exit_code == 0) {

    if ($exit_code == 1) {
        $status = "WARNING";
        $patterns_warn = " (" . $patterns_warn . ")";
    }

    # Service Output|Perfdata
    my $output = "$status - $patterns_ok/$patterns_size patterns OK$patterns_warn";
    my $perfdata = sprintf("time=%.3fs patterns=%d files=%d", $run_time, $patterns_size, $files_number);
    print "$output|$perfdata\n";

    # Long Service Output
    my $index = 1;
    foreach (@patterns_list) {
        print "$index. $_->{name} - $_->{occurences} matches found\n$_->{output}";
        $index += 1;
    }

    exit($exit_code);
}
else {
    print "UNKNOWN STATE for @logfiles\n";
    exit(3);
}
