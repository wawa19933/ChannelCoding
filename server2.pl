#!/usr/bin/perl
#################################################################
# 	Title	:	UDP Client script								# 
#	Authors	: 													#
#	Description:												#
#																#
#		 	 				_________________________________	#
#		Packet structure:  | command | number | data | [CRC] |	#
#						    ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾	#
#################################################################
# use strict;
use warnings;

use IO::Socket::INET;         	# Module that adds the socket support
use File::Basename;				# Module for extracting file name from the path
use MIME::Base64;				# Module for encoding binary data
use IO::Poll qw( POLLIN ); 		# Module for ARQ realization: for data detection in a receiving buffer
use Fcntl qw( SEEK_SET );		# Declaration of SEEK_SET flag for file seeking
use POSIX;						# For support of math functions
use String::CRC32 qw( crc32 );
use v5.14;

$\ = "\n";				# Added as an invisible last element to the parameters passed to the print() function. *doc
$| = 1;					# If nonzero, will flush the output buffer after every write() or print() function. Normally, it is set to 0. *doc
				
my $udpPort = '8849';							# Variable for port number defenition
my $tcpPort = '8850';
my ( $fileName, $fileSize, $windowsCount, %fileParts ); # Some global variables
my ( $dataSocket, $serviceSocket );
my ( $buffer, @window, @arq );
my $blockSize = 4096;						# Definding of packet portion for transmittion
my $windowSize = 80;						# ARQ Window size 
my $timeout = 0.7;
my $delim = ';';

print "======= File transfer on Perl ========";
$dataSocket = IO::Socket::INET->new (
		LocalPort 	=> $udpPort,
		Proto 		=> 'udp',
		Type		=> SOCK_DGRAM,
		Reuse 		=> 1
	) or die "Could not start the server on port $udpPort : $!";
my $serverTcp = IO::Socket::INET->new (
		LocalPort	=> $tcpPort,
		Proto 		=> 'tcp',
		Type		=> SOCK_STREAM,
		Listen 		=> 1,
		Reuse 		=> 1
	) or die "Couldn't create TCP socket on port $tcpPort : $!";

$serviceSocket = $serverTcp->accept();
if ( $serviceSocket ) {
	my $client = $serviceSocket->peername;
	my ( $port, $iaddr ) = sockaddr_in( $client );
	my $peerName = gethostbyaddr($iaddr, AF_INET);
	my $peerAddress = inet_ntoa($iaddr);
	print "Client $peerName ($peerAddress) is connected!\n";
}
$windowsCount = 0;

##		Starting the receiving loop that is controlled by 	##
##		commands from the client via Switch-like statment	##
while () 
{
	my $cmd;
	my @msg;
	if ( checkService() ) {
		$serviceSocket->recv ( $buffer, 5000 );
		@msg = split $delim, $buffer;
		$cmd = shift @msg;
	}
	# if ( checkData() ) {
	# 			$dataSocket->recv ( $buffer, 9000 );
				
	# 			# my @msg = split $delim, $buffer;
	# 			# my $num = shift @msg;
	# 			# my $encoded = shift @msg;
	# 			# my $cksum = shift @msg;
	# 			# my $data = encode_base64 ( $encoded );

	# 			# if ( $cksum eq crc32( $data ) ) {
	# 			# 	push @window, $num;
	# 			# 	$fileParts{ $num } = $data;	
	# 			# }
	# 			# else {
	# 			# 	push @arq, $num;}

	# 			# 	# 			print " UDP bytes of file received!";
	# 		}
	# print "\n\nCommand: $cmd \n";
	
	given ($cmd)
	{
		when ('INFO') {
			$fileName = shift @msg;
			$fileSize = shift @msg;
			print "$fileSize bytes of $fileName to be received...";
		}
		when ('CHECK') {
			if ( scalar (@window) < $windowSize ) {
				@window = sort @window;

				#DEBUG
				print "Window sorted: @window";

				for (my $i = $windowsCount * $windowSize + 1; $i <= ($windowsCount + 1) * $windowSize; $i++)
				{
					my $curr = shift (@window);
					if ($i ne $curr) {
						push @arq, $i;
						$i = $curr;
						print "Append \@arq[$i] with $i";
					}
					print "Cycle: $i";
				}
				$serviceSocket->send ( join ($delim, ( 'ARQ', join (':', @arq) )) );
			}
			else {							# Window Success
				serviceSocket->send ('OK');
				$windowsCount++;
				undef @arq;
				undef @window;
			}
		}

		default {
			# if ( checkData() ) {
				$dataSocket->recv ( $buffer, 9000 );
				
				my @msg = split $delim, $buffer;
				my $num = shift @msg;
				my $encoded = shift @msg;
				my $cksum = shift @msg;
				my $data = encode_base64 ( $encoded );

				if ( $cksum eq crc32( $data ) ) {
					push @window, $num;
					$fileParts{ $num } = $data;	
				}
				else {
					push @arq, $num;
				}
				print "$num) -- " . length($encoded) . " bytes of file received!";
			# }
		}
	}
	undef $cmd;
	undef $buffer;
	undef @msg;
}

close $dataSocket;
close $serviceSocket;

#################

sub checkIncome {
	my $poll = IO::Poll->new;
	$poll->mask ( 
			$serviceSocket => POLLIN,
			$dataSocket    => POLLIN 
		);
	my $result = $poll->poll ();

	if ( $result == -1 ) {
		print "Error with poll() : $!";
		return 0;
	}

	return $poll->handles( POLLIN );
}

sub checkService {
	my $time = shift || 0.125;
	my $poll = IO::Poll->new;
	$poll->mask (
		$serviceSocket => POLLIN
	);

	my $res = $poll->poll ( $time );
	if ( $res == -1 ) {
		print "Error with poll() : $!";
		return 0;
	}

	return $res;
}

sub checkData {
	my $time = shift || 0.125;
	my $poll = IO::Poll->new;
	$poll->mask (
		$dataSocket => POLLIN
	);

	my $res = $poll->poll ( $time );
	if ( $res == -1 ) {
		print "Error with poll() : $!";
		return 0;
	}

	return $res;
}