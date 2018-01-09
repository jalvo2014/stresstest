#!/usr/local/bin/perl -w

#------------------------------------------------------------------------------
# Licensed Materials - Property of IBM (C) Copyright IBM Corp. 2013
# All Rights Reserved US Government Users Restricted Rights - Use, duplication
# or disclosure restricted by GSA ADP Schedule Contract with IBM Corp
#------------------------------------------------------------------------------

#
#  perl itm_stress.pl <timestamp>
#
#     Self measurement of TEMS stress based on standard deviation of timing differences between invocations.
#
#     keep track of invocation times and from them calculate a sliding window mean and standard deviation of the statistics.
#
#     The hypothesis is that while mean time will stay quite close to target, the variation between the times will vary more
#     when the TEMS is under stress. When a situation starts late, the next interval is adjusted to be less time than usual.
#
#     This is an example program and you may use it to explore the concept.
#
#  john alvord, IBM Corporation, 18 March 2013
#  jalvord@us.ibm.com
#
# tested on AIX v5.8.2 built for aix-thread-multi
#
# $DB::single=2;   # remember debug breakpoint

use Time::HiRes qw(gettimeofday);             # need Hires timing, by microsecond

my $version = "0.10000";
my $gWin = (-e "C://") ? 1 : 0;               # 1=Windows, 0=Linux/Unix
my $local_dir = "/tmp/";                      # location of stress files
$local_dir = "c:" . $local_dir if $gWin == 1; # Stress file in Windows
my $local_file = "stress.txt";                # current data file
my $local_log  = "stress.log";                # Progress log
my $local_window = 48;                        # number of entries to consider for sliding window, zero based

my $s;                                        # Capture time of day in microseconds
my $usec;
 ($s, $usec) = gettimeofday();

my $current_time = $s + $usec/1000000;        # current time in microseconds


my $time_stamp = $ARGV[0];                    # From situation, should be Timestamp attribute value
   $time_stamp = "" if !defined $time_stamp;  #   or null if missing
my $full_file = $local_dir . $local_file;     # fully qualified names for files
my $full_log =  $local_dir . $local_log;
my @stress_data;                              # collect data from state file
my $last_time;                                # last time in microseconds
my $duration;                                 # Time since last cycle
my $old_duration;                             # After hit window limit, this is the oldest entry
my @dur_values;                               # array of durations, oldest first
my $dur_string;                               # array of durations in string form
my $prior_mean;                               # saved mean
my $prior_sums;                               # saved sum of squares for std deviation
my $current_mean;                             # curent mean
my $current_sums;                             # current sum of squares
my $k;                                        # way to could current minus 1
my $sigma;                                    # Standard Deviation estimate

open (LOGFILE,">>$full_log") || die "unable to open $full_log - $!\n";

if (-e $full_file) {                                                           # file exists
   open(MYFILE, "< $full_file") || die("Could not open $full_file\n");
   @stress_data = <MYFILE>;
   close(MYFILE);
   chomp($stress_data[0]);
   ($last_time,$prior_mean,$prior_sums) = split(" ",$stress_data[0]);          # extract recent data
   $duration = $current_time - $last_time;
   chomp($stress_data[1]);
   $dur_string = $stress_data[1];
   @dur_values = split(' ',$dur_string);                                       # extract values
   push (@dur_values, $duration);                                              # add new duration to end

   # The logic is to calculate a sliding window of mean and standard deviation.
   # Doing this interatively saves a lot of calculations.
   #
   # The logic was adapted from
   #
   #   http://www.mymathforum.com/viewtopic.php?f=44&t=14057
   #
   # which referenced
   #
   #   Donald Knuth's "The Art of Computer Programming, Volume 2: Seminumerical Algorithms", section 4.2.2
   #
   # And Knuth attributes this method to
   #
   #    B.P. Welford, Technometrics, 4,(1962), 419-420.
   #
   # M(1) = x(1), M(k) = M(k-1) + (x(k) - M(k-1)) / k
   # S(1) = 0, S(k) = S(k-1) + (x(k) - M(k-1)) * (x(k) - M(k))
   #
   # when k > N
   #
   # WM(k) = (M*k-V(k-N))/k-1)
   # WS(k) =- (V(k-N)-M(k))*(V(k-N)-M)
   #
   # M(k) = WM(k)
   # S(k) = SN(k)

   $k = $#dur_values + 1;                                           # number of new duration captures
   if ($k > 0) {
      $current_mean = $prior_mean + ($duration - $prior_mean)/$k;   # If some exist, first assume not up to sliding window
      $current_sums = $prior_sums +                                 # caclulate mean and squared sigma
           (($duration - $prior_mean)*($duration - $current_mean));
   } else {
      $current_mean = $duration;                                    # first time
      $current_sums = 0;
   }

   if ($k > $local_window) {                                        # if reached window limit, remove oldest and adjust
      $old_duration = shift (@dur_values);                          # extract oldest duration
      $old_mean = $current_mean;                                    # remember current mean
      $current_mean = ($current_mean*$k-$old_duration)/($k-1);      #  recalculate mean
      $current_sums -=
           ($old_duration-$old_mean)*($old_duration-$current_mean); # recalculate sums
      $k -= 1;
   }
   $sigma = 0;                                                      # caclculate standard deviation estimate
   $sigma = sqrt($current_sums/($k-1)) if $k > 1;
   open(MYFILE,">$full_file") || die "unable to open $full_file - $!\n";
   print MYFILE "$current_time $current_mean $current_sums\n";
   print MYFILE join(' ',@dur_values) . "\n";
   close MYFILE;
   print LOGFILE "Added entry $current_time $k $current_mean $current_sums $duration $sigma $time_stamp\n";
} else {                                                                     # startup case
   open(MYFILE,">$full_file") || die "unable to open $full_file - $!\n";
   $prior_mean = 0.0;
   $prior_sums = 0.0;
   print MYFILE "$current_time $prior_mean $prior_sums\n";
   print MYFILE "\n";
   close MYFILE;
   print LOGFILE "itm_stress.pl $version\n";
   print LOGFILE "Initial entry $current_time\n";

}
close LOGFILE;

exit 0;

# ideas
#
# 1) Find a way to generate an alert under some circumstances - perhaps a universal message generated using kshsoap.
# 2) Archive log file periodically.
# 3) Current invocation on test AIX system costs 0.3 seconds. At a five minute interval, cost is 0.1%. Consider compiled program object.
