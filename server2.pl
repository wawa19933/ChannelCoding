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
use strict;
use warnings;

use IO::Socket::INET;         	# Module that adds the socket support
use File::Basename;				# Module for extracting file name from the path
use MIME::Base64;				# Module for encoding binary data
use IO::Poll qw( POLLIN ); 		# Module for ARQ realization: for data detection in a receiving buffer
use Fcntl qw( SEEK_SET );		# Declaration of SEEK_SET flag for file seeking
use POSIX;						# For support of math functions

$\ = "\n";				# Added as an invisible last element to the parameters passed to the print() function. *doc
$| = 1;					# If nonzero, will flush the output buffer after every write() or print() function. Normally, it is set to 0. *doc
				
my $argc = @ARGV;				# Checking the number of arguments
if ($argc < 1) {				# If there is no arguments ->
	HELP_MESSAGE();				# 			print the help message
	exit;						# Exit
}
my $port = '8849';							# Variable for port number defenition
my $fileName = fileparse ( $filePath );		# Extracting the name of the file
my ( $buffer, $number, $partsCount, @arq, %fileParts ); # Some global variables
my $blockSize = 4096;						# Definding of packet portion for transmittion
my $fileSize = -s $filePath;				# Taking the size of the local file (-s is a size operator)
my $windowSize = 80;						# ARQ Window size 
my $timeout = 0.7;
my $delim = ';';

print "======= UDP Server on Perl ========";
my $socket = IO::Socket::INET->new (
		LocalPort 	=> $port,
		Port 		=> 'udp',
		Type		=> SOCK_DGRAM
	) || die "Could not start the server on port $port : $!";

##		Starting the receiving loop that is controlled by 	##
##		commands from the client via Switch-like statment	##
while () 
{
	my $rcv = $socket->recv ( my $message, $blockSize );
	my ( $port, $iaddr ) = sockaddr_in ( $rcv );
	my $peerAddress = inet_ntoa ( $iaddr );
	my $peerName = gethostbyaddr ( $iaddr, AF_INET );

	print length($message) . " bytes are received from $peerAddress ($peerName)";
	my @packet = split ';', $message;
	my $cmd = shift @packet;

	given ($cmd)
	{
		when ('DATA') {
			my $num = shift @packet;
			my $encoded = shift @packet;
			print "$num) -- " . length($encoded) . " bytes of file received!";
			$fileParts{$num} = decode_base64 ( $encoded );
		}
	}
}