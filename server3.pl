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
# use warnings;
no warnings 'uninitialized';

use IO::Socket::INET;         	# Module that adds the socket support
use File::Basename;				# Module for extracting file name from the path
use MIME::Base64;				# Module for encoding binary data
use IO::Poll qw( POLLIN ); 		# Module for ARQ realization: for data detection in a receiving buffer
use Fcntl qw( SEEK_SET );		# Declaration of SEEK_SET flag for file seeking
use POSIX;						# For support of math functions
use String::CRC32 qw( crc32 );
use Time::HiRes;
use v5.14;

$\ = "\n";				# Added as an invisible last element to the parameters passed to the print() function. *doc
$| = 1;					# If nonzero, will flush the output buffer after every write() or print() function. Normally, it is set to 0. *doc
				
my $udpPort = '8849';							# Variable for port number defenition
my $tcpPort = '8850';
my ( $fileName, $fileSize, $windowsCount, %fileParts ); # Some global variables
my ( $dataSocket, $serviceSocket );
my ( $buffer, @check, @arq );
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
my $stop = '0';
##		Starting the receiving loop that is controlled by 	##
##		commands from the client via Switch-like statment	##
while () {
	while ( $stop eq '0' ) {
	eval {
		local $SIG{ALRM} = sub { die "Alarm!!"; };
		alarm 3;
			$dataSocket->recv ( $buffer, 9000 );
			my @msg = split $delim, $buffer;
			my $num = shift @msg;
			my $data = decode_base64 ( shift (@msg) );
			my $cksum = shift @msg;

			if ( crc32 ($data) eq $cksum ) {
				$fileParts{ $num } = $data;
			}
			else {
				push @arq, $num;
			}
			print "Packet : $num";
		alarm 0;
	};
		if ( $@ ) {
			die unless $@ eq "Timeout for socket receive"; # propagate unexpected errors
			# timed out
			$stop = '1';
		}
		else {
			print "No Timeout of reception";
			# didn't
		}
	}
	my $ii = 0;
	my @rcv = sort ( keys (%fileParts) );
	
	if ( @arq ) {
		foreach my $n (@arq) {
			if(!scalar(grep { $_ eq $n } @rcv)) {
				push @arq, $n;	
			}
		}
	} 
	else {
		foreach my $n ( @rcv ) {
			$ii++;
			if ( $ii ne $n ) {
				push @arq, $ii;
				print "Append arq with: $ii ne $n";
				$ii = $n;
			}
		}
	}
	if ( !@arq ) {

	}
	$serviceSocket->send ( join ( ';', ('ARQ', join(':', @arq)) ) );
}