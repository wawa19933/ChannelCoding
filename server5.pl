#!/usr/bin/perl
#################################################################
# 	Title	:	UDP Client script								# 
#	Authors	: 													#
#	Description:												#
#																#
#		 	 				_______________________				#
#		Packet structure:  | number | data | [CRC] |			#
#						    ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾				#
#################################################################
# use strict;
# use warnings;
no warnings 'uninitialized';

use IO::Socket::INET;         	# Module that adds the socket support
use File::Basename;				# Module for extracting file name from the path
use MIME::Base64;				# Module for encoding binary data
use IO::Poll qw( POLLIN ); 		# Module for ARQ realization: for data detection in a receiving buffer
use Fcntl qw( SEEK_SET );		# Declaration of SEEK_SET flag for file seeking
use POSIX;						# For support of math functions
use Digest::MD5 qw( md5_hex md5_base64 );
use String::CRC32 qw( crc32 );
use Time::HiRes qw( gettimeofday tv_interval );
use v5.12;

$\ = "\n";				# Added as an invisible last element to the parameters passed to the print() function. *doc
$| = 1;					# If nonzero, will flush the output buffer after every write() or print() function. Normally, it is set to 0. *doc
				
my $udpPort = '8849';							# Variable for port number defenition
my ( $fileName, $fileSize, $fileHash, $packetsCount, @fileArray, @rcvNumbers, @repeated ); # Some global variables
my ( $buffer, @arq, @prevArq, %parts );
my ( $totalBytes, $totalReceived, $totalPackets, $totalTime ); #
my $blockSize = 1300;						# Definding of packet portion for transmittion
my $delim = ';';

print "======= File transfer on Perl ========";
my $udpSocket = IO::Socket::INET->new (
		LocalPort 	=> $udpPort,
		Proto 		=> 'udp',
		Type		=> SOCK_DGRAM,
		Reuse 		=> 1
	) or die "Could not start the server on port $udpPort : $!";

$totalPackets = 0;
$totalTime = 0;
$totalBytes = 0;
$totalReceived = 0;
			
#------------------------------------------------------------------------------------------------------------------------------------
##		commands from the client via Switch-like statment	##
##		Starting the receiving loop that is controlled by 	##
#------------------------------------------------------------------------------------------------------------------------------------
my $progStart = [ gettimeofday ];
my $startTime;
#------------------------------------------------------------------------------------------------------------------------------------
my $checkFlag = '0';
my $checkTimeout = 0;
while () {
	my $receptionTime = [ gettimeofday ];
	my $rcv = $udpSocket->recv ( $buffer, 7777 );
	my @msg = split $delim, $buffer;
	my $cmd = shift @msg;

	# my $last;
	# if ( ($cmd eq 'REPEAT') and ($last ne 'REPEAT') ) {
	# 	print "REPEAT now";
	# }
	# $last = $cmd;	

	given ( $cmd )
	{
		when ('INFO') {
			my ( $port, $addr ) = sockaddr_in ( $rcv );
			my $peerAddress = inet_ntoa ( $addr );
			sendACK ();

			$fileName  =  shift @msg;
			$fileSize  =  shift @msg;
			$blockSize =  shift @msg;
			$fileHash  =  shift @msg;
			$packetsCount = shift @msg or ceil ( $fileSize / $blockSize );
			
			$startTime = [ gettimeofday ];

			print "Receiving \'$fileName\'\t$fileSize bytes in $packetsCount parts from $peerAddress ...";
		}
		when ('DATA') { 
			$checkFlag = '0';
			my $num  = shift @msg;
			my $data = decode_base64 ( shift @msg ); 
			my $sum  = shift @msg;

			if ( $sum ne md5_hex ($data) ) {
				print "$num --> Checksums are NOT equal!!";
				push @arq, $num;
			} 
			else {
				# if ( length ($data) != $blockSize ) {
				# 	print "Data piece is too small ". length($data). "/$blockSize bytes";
				# }
				$parts{ $num } = $data;
				# $file[ $num - 1 ] = $data;
				# push @rcvNumbers, $num;
			}

			$totalBytes += length $data;
			$totalReceived += length $buffer;
			$totalPackets ++;
			
			my $rcvTime = tv_interval ($receptionTime);
			if ( $rcvTime > 1 ) {
				print "$num --> $rcvTime seconds!";
			}
		}
		when ('CHECK') {
			if ( $checkFlag eq '0' ) {
				$checkFlag = '1';
				$checkTimeout = [ gettimeofday ];
				my @nums = keys %parts;
				my $receivedPieces = scalar @nums;
				
				my $ts1 = tv_interval ( $startTime );
				print "$receivedPieces \/ $packetsCount packets are received in $ts1 seconds";
				$ts1 = [ gettimeofday ];

				if ( @prevArq ) {
					foreach my $n ( @prevArq ) {
						my @gr = grep { $n eq $_ } @repeated;
						if ( !scalar ( @gr ) ) {
							push @arq, $n;
						}
					}
				}
				else {
					foreach my $n ( 1 .. $packetsCount ) {
						my @gr = grep { $n eq $_ } @nums;
						if ( !scalar ( @gr ) ) {
							push @arq, $n;
						}
					}
				}
				if ( @arq ) {
					if ( $#prevArq ne $#arq ) {
						@prevArq = @arq;
					}

					$udpSocket->send ( join $delim, ('ARQ', join( ':', @arq )) );

					# print "Received: ". join (',', checkOrder ( @nums ));
					print "Size of ARQ: ". scalar @arq;
				} 
				else {
					sendACK ();
				}

				print "CHECK -->". tv_interval($ts1)." seconds!";
				$checkTimeout = 0;
			}
			elsif ( $checkTimeout > 5 ) {
				$checkFlag = '0';
			}
			undef @arq;
			$checkTimeout ++;
		}
		when ('REPEAT') {
			$checkFlag = '0';
			my $num = shift @msg;
			my $data = decode_base64 ( shift @msg ); 
			my $sum = shift @msg;

			if ( $sum ne md5_hex ($data) ) {
				print "$num --> Checksums are NOT equal";
			}
			else {
				if ( $blockSize lt length ($data) ) {
					print "Data length: ". length $data;
				}
				# $file[ $num - 1 ] = $data;
				$parts{ $num } = $data;
				# print "Repeated: $num";
				push @repeated, $num;

				$totalBytes += length $data;
				$totalReceived += length $buffer;
				$totalPackets ++;
			}
			my $rcvTime = tv_interval ($receptionTime);
			# print "REPEAT: receiving time $rcvTime, work time: ". tv_interval($tt);
			if ( $rcvTime > 1 ){
			}
		}
		when ('FINISH') {
			my $md5 = saveFile ();
			my ( $clientTime, $cksum, $clientBytes, $clientPackets ) = @msg;
			sendACK ();
			findDuplicates (keys %parts);

			print "\n----------";
			print "File '$fileName' is written - ". (-s $fileName). " bytes";
			print "Parts total: ". scalar (keys %parts);
			print "Repeated count: ". scalar ( @repeated );
			print "";
			print "MD5 (written) : $md5";
			print "MD5 (original): $fileHash";
			print "Time: ". tv_interval ($startTime). " seconds";

			resetVars ();
		}
	}
}

print "\nTotal packets: $totalPackets, size of array: ". scalar (keys %parts);
print "Total received $totalReceived bytes and $totalBytes bytes of file";
print "Finish " . tv_interval ( $startTime ) . " seconds";

#------------------------------------------------------------------------------------------------------------------------------------
#------------------------------------------------------------------------------------------------------------------------------------
sub checkOrder {
	my $c = 0;
	my @arr = sort { $a <=> $b } @_;
	my ($first, $last, $curr, @res);
	$first = 1;
	foreach my $n ( @arr ) {
		$last = $c;
		$c++;
		if ( $n ne $c ) {
			if ( $first ne $last ) {
				push @res, "$first-$last";
			}
			else {
				push @res, "$first";
			}
			$c = $n;
			$first = $n;
		}
	}
	return @res;
}

sub sendACK {
	$udpSocket->send ('OK');
}

sub findDuplicates {
	my ( @array ) = @_;
	my %seen;
	foreach my $string ( @array ) {
	    next unless $seen{ $string } ++;
	    print "'$string' is duplicated.\n";
	}
}

sub saveFile {
	# my ( @data ) = @_;
	# my $dt = join('', @data);
	my $fromHash;
	my @values;
	foreach my $n ( 1 .. $packetsCount ) {
		$fromHash .= $parts{ $n };
		$values[ $n - 1 ] = $parts{ $n };
	}
	print "\n Hash: ". scalar(keys %parts). " elements, ". length($fromHash). " bytes";

	open my $fh, "+>", $fileName or die "Error with opening : $!";
	binmode $fh;

	$\ = "";
	print $fh "$fromHash";
	
	seek $fh, 0, 0;
	my $sum = Digest::MD5->new()->addfile($fh);
	
	$\ = "\n";
	# print "MD5 (hash): ". md5_hex ($fromHash). "  ". length $fromHash;
	# print "MD5 (hash1): ". md5_hex (join('', @values)). "  ". scalar @values;
	# print "MD5 (array): ". md5_hex ($fromHash). "  ". length $fromHash;
	
	close $fh;
	return $sum->hexdigest;
}

sub checkUdp {
	my $timeOut = shift or 0.1;
	my $poll = IO::Poll->new();
	$poll->mask ( $udpSocket => POLLIN );

	my $res = $poll->poll( $timeOut );
	if ( $res == -1 ) {
		print "Error with polling of TCP socket : $!";
		return 0;
	}

	return $res;
}

sub resetVars {
	undef @arq;
	undef @prevArq;
	# undef @file;
	undef $fileName;
	undef $fileSize;
	undef $fileHash;
	undef $packetsCount;
	undef @rcvNumbers;
	undef @repeated;
	undef $buffer;
	undef %parts;
	undef $totalBytes;
	undef $totalPackets;
	undef $totalReceived;
	undef $totalTime;
}