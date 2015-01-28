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
# my $tcpPort = '8850';
my ( $fileName, $fileSize, $fileHash, $packetsCount, @file, @numbers, @repeated ); # Some global variables
my ( $buffer, @check, @arq, @prevArq, %parts );
my ( $totalBytes, $totalReceived, $totalPackets, $totalTime ); #
my $blockSize = 1300;						# Definding of packet portion for transmittion
# my $windowSize = 80;						# ARQ Window size 
# my $timeout = 0.7;
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
my $startTime = [ gettimeofday ];
while () {
	my $receptionTime = [ gettimeofday ];
	my $rcv = $udpSocket->recv ( $buffer, ($blockSize + 1000) );
	my @msg = split $delim, $buffer;
	my $cmd = shift @msg;

	print "Incoming $cmd:";

	given ( $cmd )
	{
		when ('INFO') {
			my ( $port, $addr ) = sockaddr_in ( $rcv );
			my $peerName = gethostbyaddr ( $addr, AF_INET );
			my $peerAddress = inet_ntoa ( $addr );
			$fileName = shift @msg;
			$fileSize = shift @msg;
			$blockSize = shift @msg;
			$fileHash = shift @msg;
			$packetsCount = ceil ( $fileSize / $blockSize );
			$startTime = [ gettimeofday ];

			print "Receiving \'$fileName\'\t$fileSize bytes";
			print "\tfrom $peerName ( $peerAddress )...";
			sendACK ();
		}
		when ('DATA') { 
			my $num = shift @msg;
			my $data = decode_base64 ( shift @msg ); 
			my $sum = shift @msg;

			if ( $sum ne md5_hex ($data) ) {
				print "$num --> Checksums are NOT equal";
			}

			$parts{ $num } = $data;
			$file[ $num - 1 ] = $data;
			push @numbers, $num;

			$totalBytes += length $data;
			$totalReceived += length $buffer;
			$totalPackets ++;
			
			my $rcvTime = tv_interval ($receptionTime);
			if ( $rcvTime > 0.9 ){
				print "$num --> $rcvTime seconds!";
			}
		}
		when ('REPEAT') {
			my $num = shift @msg;
			my $data = decode_base64 ( shift @msg ); 
			my $sum = shift @msg;

			if ( $sum ne md5_hex ($data) ) {
				print "$num --> Checksums are NOT equal";
			}
			# else {
				$file[ $num - 1 ] = $data;
				$parts{ $num } = $data;
				push @numbers, $num;
				push @repeated, $num;
			# }

			$totalBytes += length $data;
			$totalReceived += length $buffer;
			$totalPackets ++;
			
			my $rcvTime = tv_interval ($receptionTime);
			if ( $rcvTime > 0.9 ){
				print "$num --> $rcvTime seconds!";
			}

		}
		when ('CHECK') {
			my $pacNum = scalar @numbers;
			my $ts1 = tv_interval ( $startTime );
			print "$pacNum \/ $packetsCount packets are received in $ts1 seconds";
			$ts1 = [gettimeofday];

			if ( @prevArq ) {
				foreach my $n ( @prevArq ) {
					if ( !scalar ( grep { $n eq $_ } @numbers ) ) {
						# print "From PrevARQ - number $n";
						push @arq, $n;
					}
				}
			}
			else {
				foreach my $n ( 1 .. $packetsCount ) {
					if ( !scalar ( grep { $n eq $_ } @numbers ) ) {
						# print "From ARQ - number $n";
						push @arq, $n;
					}
				}
			}

			if ( @arq ) {
				if ( $#prevArq ne $#arq ) {
					@prevArq = @arq;
				}

				$udpSocket->send ( join $delim, ('ARQ', join( ':', @arq )) );

				print "Received: ". join (', ', checkOrder ( @numbers ));
				# print "\n>> Sending ARQ... (". tv_interval($ts1). " seconds)";
				print "Size of ARQ: ". scalar @arq;
			} 
			else {
				$udpSocket->send ( 'OK' );
			}
			undef @arq;
			# print join ':', @arq;
		}
		when ('FINISH') {
			my $md5 = saveFile ( @file );
			my ( $clientTime, $cksum, $clientBytes, $clientPackets ) = @msg;

			findDuplicates (@numbers);
			print "\n----------";
			print "MD5 (saved): $md5";
			print "MD5 (\@file): ". md5_hex (join '', @file);
			print "MD5 (received): $cksum";
			print "MD5 (original): $fileHash";
			print "";
			print "File $fileName is written, ". (-s $fileName). " bytes";
			print "Packets total: ". scalar ( @file );
			last;		
		}
	}
}


print "\nTotal packets: $totalPackets, size of array: ". scalar @file;
print "Total received $totalReceived bytes and $totalBytes bytes of file";
print "Finish " . tv_interval ( $startTime ) . " seconds";

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
	my ( @data ) = @_;
	my $wr = join('', @data);
	my $dt;
	
	foreach my $n ( 1 .. $packetsCount ) {
		$dt .= $parts{ $n };
	}

	open my $fh, "+>", $fileName or die "Error with opening : $!";
	binmode $fh;

	$\ = "";
	print $fh "$dt";
	
	seek $fh, 0, 0;
	my $sum = Digest::MD5->new()->addfile($fh);
	
	close $fh;
	$\ = "\n";
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
	# while ( ) {
	# 	eval {
	# 		local $SIG{ALRM} = sub { die "Alarm!!"; };
	# 		alarm 30;
	# 			$udpSocket->recv ( $buffer, $maxPacket );
	# 			my @msg = split $delim, $buffer;
	# 			my $num = shift @msg;
	# 			my $data = decode_base64 ( shift (@msg) );
	# 			my $cksum = shift @msg;

	# 			print "Packet : $num is received";
	# 		alarm 0;
	# 			if ( $num eq 'END' ) {
	# 				$stop = 1;
	# 				last;
	# 			}

	# 			if ( $cksum ne crc32($data) ) {
	# 				print "CRC: $cksum != ".crc32($data);
	# 			}

	# 			$file[ $num ] = $data;

	# 			$totalReceived += length $buffer;
	# 			$totalBytes += length $data;
	# 			$totalPackets ++;

	# 			push @numbers, $num;
	# 	};
	# 	if ( $@ ) {
	# 		# $stop = 1;					# If alarm throws exception
	# 		print "Alarm had been triggered";
	# 		# last;
	# 	}
	# 	# else { }
	# }

	# print "MD5: " . Digest::MD5->new()->add ( join ( '', @file ) )->hexdigest;

	# if ( @prevArq ) {
	# 	foreach my $n (@prevArq) {
	# 		if( !scalar ( grep { $_ eq $n } @numbers ) ) {
	# 			push @arq, $n;	
	# 			# print " ARQ routine (true): $n";
	# 		}
	# 	}
	# } 
	# else {
	# 	my $t1 = [ gettimeofday ];
	# 	for ( my $c = 1; $c < $numOfPackets; $c++ ) {
	# 		if ( !scalar ( grep { $_ eq $c } @numbers ) ) {
	# 			# print " ARQ routine (false): $c";
	# 			push @arq, $c;
	# 		}
	# 	}
	# 	print "Time for $numOfPackets packets: " . tv_interval ( $t1 );
	# }
	# print "ARQ list: \@arq";
	# if ( @arq ) {
	# 	$tcpSocket->send ( join ($delim, ('ARQ', join (':', @arq))) );
	# } 
	# else {
	# 	$tcpSocket->send ( 'OK' );
	# 	last;
	# }

	# @prevArq = @arq;
	# $#arq = -1;

# MD5 (saved): ece16dffed4254a9c2d1844f0eb76a82
# MD5 (@file): a0e6ed23aad2bfd5d5f797325a7a2f82

# MD5 (saved): c2276528f9081d1f0127ed7213d65964
# MD5 (@file): 309848bbf8265c5d7eceb861d5aa87b9
