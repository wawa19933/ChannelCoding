#!/usr/bin/perl
#################################################################
# 	Title	:	UDP Client script								# 
#	Authors	: 													#
#	Description:												#
#																#
#		 	 				_________________________________	#
#		Packet structure:  | number |	   data 	|  [CRC] |	#
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
use String::CRC32;				# Module for CRC32 calculation function
use Term::ProgressBar;
use Time::HiRes;

$\ = "\n";			# Added as an invisible last element to the parameters passed to the print() function. *doc
$| = 1;				# If nonzero, will flush the output buffer after every write() or print() function. Normally, it is set to 0. *doc
				
my $filePath = shift; 	     				# Taking the file's path from the FIRST argument
my $hostAddr = shift || 'localhost';		# Taking the server's address from the SECOND argument
my $udpPort = '8849';						# Variable for port number of the UDP socket for data transmission
my $tcpPort = '8850';						# Port for TCP connection for service info exchange
my $fileName = fileparse ( $filePath );		# Extracting the name of the file
my $fileSize = -s $filePath;				# Taking the size of the local file (-s is a size operator)
my $blockSize = 4096;						# Definding of packet portion for transmittion
my $windowSize = 80;						# ARQ Window size 
my $timeout = 0.7;							# Global timeout variable
my $delim = ';';							# Global delimiter for packets' fields
my ( $buffer, $number, $partsCount, $windowCount, @arq); 	# Some global variables
my ( $dataSocket, $serviceSocket );					# 
###	END of declarations

print "Going to send $fileName to $hostAddr";	

#	Opening the specified file in BINARY form for reading only
open FILE, '<', $filePath or die "Can not open the file!!! $filePath: $!";
binmode FILE;

#	Creating a UDP socket for file parts transmission to the specified host
$dataSocket = IO::Socket::INET->new (
		PeerAddr 	=> $hostAddr,
		PeerPort 	=> $udpPort,
		Proto 		=> 'udp',
		Type		=> SOCK_DGRAM
	) or die "Couldn't create UDP socket!!!: $!";
#	Creating a TCP socket for service info transmission
$serviceSocket = IO::Socket::INET->new (
		PeerAddr	=> $hostAddr,
		PeerPort	=> $tcpPort,
		Proto 		=> 'tcp',
		Reuse 		=> 1,
		Type		=> SOCK_STREAM
	) or die "Couldn't create TCP socket! : $!";
$number = 0;									# Initialization of the counter for transmitions' number
my $progressBar = Term::ProgressBar->new ( $fileSize ); # Initialization of a progress bar with the size of the file

#	1)	---	Sending a file info 
$serviceSocket->send ( join $delim, ( 'INFO', $fileName, $fileSize ) );

while ( !eof(FILE) ) 
{
	my $bytes = read ( FILE, $buffer, $blockSize ) || 		# Reading the $blockSize bytes from the file
				die "Error during file reading : $!";
	
	$number ++;
	$bytes = $dataSocket->send ( join ( $delim, ($number, encode_base64 ( $buffer ), crc32($buffer)) ) ) || 
				die "Error during sending : $!"; 	# Sending the Base64 encoded part of the file and checksum for this part

	$progressBar->update ( tell FILE );

	# # DEBUG
	# my $ss = $number * $blockSize;
	# print "$number) Calculated position: $ss \/ Real: " . tell FILE;
}

#	2.2) -- Checking and repeating
my $ack = 'KO';
while ( ( $ack ne 'OK' ) || ( $c < 2 ) ) 
{
	$c++;
	# $serviceSocket->send ('CHECK');
	$serviceSocket->recv ( $buffer, 7000 );
	if ( $buffer ) {
		my @msg = split $delim, $buffer;
		$ack = shift @msg;
		@arq = split (':', shift (@msg));

		foreach my $n (@arq) {
			repeatPart ( $n );
		}
	}
}