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
use IO::Socket::INET;         				# Module that adds the socket support
use MIME::Base64;							# Module for encoding binary data
use POSIX;									# For support of math functions
use IO::Poll qw( POLLIN ); 					# Module for ARQ realization: for data detection in a receiving buffer
use Fcntl qw( SEEK_SET );					# Declaration of SEEK_SET flag for file seeking
use Digest::MD5 qw( md5_hex md5_base64 );	# For MD5 hash sum
use Time::HiRes qw( gettimeofday tv_interval ); # For time measurement
use v5.12;									# For given()/when() statements support

$\ = "\n";				# Added as an invisible last element to the parameters passed to the print() function. *doc
$| = 1;					# If nonzero, will flush the output buffer after every write() or print() function. Normally, it is set to 0. *doc
				
my $udpPort = '8849';									# Variable for port number defenition
my ( $fileName, $fileSize, $fileHash, $piecesCount, ); 	# Some global variables for file Info
my ( $buffer, @arq, @prevArq, @lastReceived, %file, @fileArray, @repeated );	# Global temporary variables
my $blockSize = 1300;									# Definding of packet portion for transmittion
my $maxBuffer = 16000;									# Max size of receiving buffer
my $delim = ';';											# For global message delimiter

my $totalPackets = 0;
my $totalTime = 0;
my $totalBytes = 0;
my $totalReceived = 0;
my $progStart = [ gettimeofday ];
my $checkFlag = '0';
my $checkTimeout = 0;
my $arqNumber = 0;
my $startTime = 0;
#------------------------------------------------------------------------------------------------------------------------------------
# Start
#------------------------------------------------------------------------------------------------------------------------------------
print "======= File transfer on Perl ========";
my $udpSocket = IO::Socket::INET->new (
		LocalPort 	=> $udpPort,
		Proto 		=> 'udp',
		Type		=> SOCK_DGRAM,
		Reuse 		=> 1
	) or die "Could not start the server on port $udpPort : $!";
#------------------------------------------------------------------------------------------------------------------------------------
#------------------------------------------------------------------------------------------------------------------------------------
#		commands from the client via Switch-like statment	#
#		Starting the receiving loop that is controlled by 	#
#------------------------------------------------------------------------------------------------------------------------------------
while () {
	my $receptionTime = [ gettimeofday ];
	my $rcv = $udpSocket->recv ( $buffer, $maxBuffer );
	my @msg = split $delim, $buffer;
	my $cmd = shift @msg;
	print "CMD: $cmd";
	given ( $cmd )
	{
		when ('INFO') {
			sendACK ();
			my ( $port, $addr ) = sockaddr_in ( $rcv );
			my $peerAddress = inet_ntoa ( $addr );

			$fileName  =  shift @msg;
			$fileSize  =  shift @msg;
			$blockSize =  shift @msg;
			$piecesCount = shift @msg or ceil ( $fileSize / $blockSize );
			
			$startTime = [gettimeofday];

			print "Receiving '$fileName'\t$fileSize bytes in $piecesCount parts from $peerAddress ...";
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
				# $file{ $num } = $data;
				$fileArray[ $num - 1 ] = $data;
				push @lastReceived, $num;
			}

			$totalBytes += length $data;
			$totalReceived += length $buffer;
			$totalPackets ++;
			
			my $rcvTime = tv_interval ($receptionTime);
			if ( $rcvTime > 1.1 ) {
				print "$num --> $rcvTime seconds!";
			}
		}
		when ('CHECK') {
			if ( scalar (@fileArray) eq $piecesCount ) {
				print "All pieces are received!";
				sendACK ();
				break;
			}
			if ( $checkFlag eq '0' ) {
				$checkFlag = '1';
				$checkTimeout = [ gettimeofday ];
				
				my $receivedPieces = scalar @fileArray;
				if ( $receivedPieces eq $piecesCount ) {
					break;
				}
				my $ts1 = tv_interval ( $startTime );
				print "$receivedPieces \/ $piecesCount packets are received in $ts1 seconds";

				$ts1 = [ gettimeofday ];

				if ( @prevArq ) {
					foreach my $n ( @prevArq ) {
						my @gr = grep { $n eq $_ } @lastReceived;
						if ( !scalar ( @gr ) ) {
							push @arq, $n;
						}
					}
				}
				else {
					foreach my $n ( 1 .. $piecesCount ) {
						my @gr = grep { $n eq $_ } @lastReceived;
						if ( !scalar ( @gr ) ) {
							push @arq, $n;
						}
					}
				}
				if ( @arq ) {
					@prevArq = @arq;
					$udpSocket->send ( join $delim, ('ARQ', join( ':', @arq )) );
					print "Size of ARQ: ". scalar @arq;
				} 
				else {
					sendACK ();
				}

				# print "CHECK -->". tv_interval($ts1)." seconds!";
			}
			else {
				if ( tv_interval ($checkTimeout) > 0.1 ) {
					$checkFlag = '0';
				}
			}
			undef @arq;
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
				# $file{ $num } = $data;
				$fileArray[ $num - 1 ] = $data;
				push @lastReceived, $num;
				push @repeated, $num;

				$totalBytes += length $data;
				$totalReceived += length $buffer;
				$totalPackets ++;
			}
			
			my $rcvTime = tv_interval ( $receptionTime );
			if ( $rcvTime > 1 ){
				print "$num --> $rcvTime seconds!";
			}
		}
		when ('FINISH') {
			my $md5 = saveFile ();
			$totalTime = tv_interval ($startTime);
			my ( $clientTime, $cksum, $clientBytes, $clientPackets ) = @msg;
			$fileHash = $cksum;
			sendACK ();
			sendSummary( ($md5, scalar(@repeated), $totalTime) );

			print "\n----------";
			print "File '$fileName' is written - ". (-s $fileName). " bytes";
			print "Parts total: ". scalar (@fileArray);
			print "Repeated count: ". scalar ( @repeated );
			print "";
			print "MD5 (written) : $md5";
			print "MD5 (original): $fileHash";
			print "Time: $totalTime seconds / $clientTime seconds (client time)";

			resetVars ();
		}
	}

	undef @arq;
	undef @lastReceived;
}

print "\nTotal packets: $totalPackets, size of array: ". scalar (@fileArray);
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
	# foreach my $n ( 1 .. $piecesCount ) {
	# 	$fromHash .= $parts{ $n };
	# 	$values[ $n - 1 ] = $parts{ $n };
	# }
	my $data = join '', @fileArray;
	open my $fh, "+>", $fileName or die "Error with opening : $!";
	binmode $fh;

	$\ = "";
	print $fh "$data";
	
	seek $fh, 0, 0;
	my $sum = Digest::MD5->new()->addfile($fh);
	
	$\ = "\n";
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

sub sendSummary {
	for ( 1 .. 3 ) {
		$udpSocket->send ( join $delim, shift ( @_ ) );
	}
}

sub resetVars {
	undef @arq;
	undef @prevArq;
	undef @fileArray;
	undef @lastReceived;
	undef @repeated;
	undef $fileName;
	undef $fileSize;
	undef $fileHash;
	undef $piecesCount;
	undef $buffer;
	undef %file;

	$totalPackets = 0;
	$totalTime = 0;
	$totalBytes = 0;
	$totalReceived = 0;
	$progStart = [ gettimeofday ];
	$checkFlag = '0';
	$checkTimeout = 0;
}