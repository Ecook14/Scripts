#!/usr/bin/perl
use strict;
use warnings;
use Socket qw(inet_aton);
my @cidrwarn; # {cidr: string, ip: ip2int(), width: int, who string}

load_cidr($_) for "Cloudflare", "CodeGuard", "Pingdom", "SingularCDN", "SiteLock", "VaultPress";
push @cidrwarn,
        map { {cidr => $_, ip => unpack("N", inet_aton($_)), width => 32, who => "Local"} }
        grep { $_ ne "127.0.0.1" }
        qx(ifconfig) =~ /(?:inet addr:|inet )([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})/g;

sub run {
        my @netstat = `netstat -pant`;

        my $portcheck = $ARGV[0];
        if ( defined($portcheck) && $portcheck =~ /^[0-9]+$/ ) {
                my %ips;
                foreach (@netstat) {
                        if ( /^tcp\s+\d\s+\d\s+[0-9\.|0-9A-Za-z\.:]+:${portcheck}\s+([0-9\.|0-9A-Za-z\.:]+):/ ) {
                                chomp;
                                my $ip = $1;
                                if ( $ip !~ /^::$/ ) {
                                        $ips{$ip}++;
                                }
                        }
                }
                my $count = 0;
                print "[+] Highest connections on port $portcheck\n";
                foreach my $number ( sort {$ips{$b} <=> $ips{$a}} keys %ips ) {
                        if ( $count <= 10 ) {
                                if ($number) {
                                        print "\t$ips{$number} $number";
                                        if ( my @cidr = cidrcheck($number) ) {
                                                print " *** ", join(",", @cidr), " IP ***";
                                        }
                                        print "\n";
                                        $count++;
                                }
                        }
                }
                my $total = 0;
                foreach my $key ( keys %ips ) {
                        if ($key) {
                                $total += $ips{$key};
                        }
                }
                print "\n[+] TOTAL: $total\n";
        } else {
                my %ports;
                my %ips;
                foreach (@netstat) {
                        my ($port, $ip);
                        if ( /^tcp\s+\d\s+\d\s+[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:([0-9]+)\s+([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}):[0-9]+\s+/ ) {
                                chomp;
                                $port = $1;
                                $ip = $2;
                        } elsif ( /^tcp\s+\d\s+\d\s+[0-9\.|0-9A-Za-z\.:]+:([0-9]+)\s+([0-9\.|0-9A-Za-z\.:]+):[0-9]+\s+/ ) {
                                chomp;
                                $port = $1;
                                $ip = $2;
                        }
                        if (defined $port && defined $ip) {
                                $ports{$port}++;
                                $ips{$ip}++;
                        }
                }

                my $count = 0;
                print "[+] Top Connections by IP any port:\n";
                foreach my $number ( sort {$ips{$b} <=> $ips{$a}} keys %ips ) {
                        if ( $count <= 10 ) {
                                if ($number) {
                                        print "\t$ips{$number} $number";
                                        if ( my @cidr = cidrcheck($number) ) {
                                                print " *** ", join(",", @cidr), " IP ***";
                                        }
                                        print "\n";
                                        $count++;
                                }
                        }
                }

                $count = 0;
                print "\n[+] Connections by port:\n";
                foreach my $number ( sort {$ports{$b} <=> $ports{$a}} keys %ports ) {
                        if ( $count <= 10 ) {
                                if ($number) {
                                        print "\t$ports{$number} $number\n";
                                        $count++;
                                }
                        }
                }

                my $total = 0;
                foreach my $key ( keys %ports ) {
                        if ($key) {
                                $total += $ports{$key};
                        }
                }

                print "\n[+] TOTAL: $total\n";
        }
}

sub load_cidr {
        my ($who, $file) = @_;
        $file = "/etc/firewall/conf/".lc($who) unless defined $file;
        if ( open my $f, "<", $file ) {
                while ( defined(my $line = <$f>) ) {
                        next unless $line =~ m!^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})(?:/(\d+))?$!;
                        my ($ip, $width) = ($1, $2);
                        $width = 32 unless defined $width;
                        push @cidrwarn, {
                                cidr => $width == 32 ? $ip : "$ip/width",
                                ip => unpack("N", inet_aton($ip)),
                                width => $width,
                                who => $who
                        };
                }
        }
}

sub cidrcheck {
        my ($ip) = @_;
        my @who;
        $ip = unpack("N", inet_aton($ip));

        for my $cidr (@cidrwarn) {
                my $mask = $ip & (-1 << (32 - $cidr->{width}));
                next unless $mask == $cidr->{ip};
                push @who, $cidr->{who};
        }
        return sort @who;
}

run();
