#!/usr/bin/perl
#################################################################
# 	Title	:	UDP Client script								# 
#	Authors	: 													#
#	Description:												#
#																#
#		 	 				 __________________________________	#
#		Packet structure:	| command | number | data | [CRC] |	#
#						    ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾	#
#################################################################

use strict;
use warnings;

use IO::Socket::INET;         	# Module that adds the socket support
use File::Basename;				# Module for extracting file name from the path
use MIME::Base64;				# Module for encoding binary data
use Digest::CRC qw( crc64 crc32 crc ); # Module for CRC calculation
use IO::Poll qw(POLLIN POLLOUT POLLHUP); # Module for ARQ realization: for data detection in a receiving buffer

$\ = "\n";						# Added as an invisible last element to the parameters passed to the print() function. *doc
$| = 1;							# If nonzero, will flush the output buffer after every write() or print() function. Normally, it is set to 0. *doc
				
$argc = @ARGV;					# Checking the number of arguments
if ($argc < 1) {
	HELP_MESSAGE();
	exit;
}

my $filePath = shift; 	     			# Taking the file's path from the FIRST argument
my $hostAddr = shift or 'localhost';	# Taking the server's address from the SECOND argument
my $port = '8849';						# Variable for port number defenition
my $filename = fileparse ( $filePath );	# Extracting the name of the file
my ( $buffer, $counter, $sz = 1024, @arq ); # Some global variables

print "Going to send $filename to $hostAddr...";

#	Opening the specified file in BINARY form for reading only
open FILE, '<', $filePath or die "Can not open the file!!! $filePath: $!";
binmode FILE;

#	Creating the UDP socket for communication with specified host
my $socket = IO::Socket::INET->new(
				PeerAddr 	=> $hostAddr,
				PeerPort 	=> $port,
				Proto 		=> 'udp',
				Type		=> SOCK_DGRAM
	) or die "Couldn't create socket!!!: $!";


# 1) --	Sending the file name to server	#################################
$counter = 0;
my @msg = ( 'NAME', $counter, $filename );
$socket->send ( join ';', @msg ) or die "Sending error: $!";

# 2) --	Sending the whole file by parts of $sz Bytes size
my $check = IO::Poll->new;					# Creating an object for poll() call
$check->mask ( $socket => POLLIN );			# and watching for incoming data
 
while ( read FILE, $data, $sz > 0 ) {							# This loop performs reading 
	print sendData ( $data ) . " bytes are sent to $hostAddr";
	
	if ( $check->poll (15) ) {
		my $arqMsg;
		$socket->recv ( $arqMsg, 255 );
		my @packet = split ';', $arqMsg;
	}
}

$counter++;
# $message = "$counter;EXIT;";
$socket->send( $message ) or die "Sending error: $! $endl";

print "\n";

close FILE;       # Closing the file

sub HELP_MESSAGE {
	print "\nUsage: client.pl [host] [file] \n\n";
}

sub sendData {
	my $rawData = shift;					# First parameter of the function
	my $encoded, $hash;
	
	$counter ++;
	$hash = crc32 ( $rawData );
	$encoded = encode_base64 ( $rawData );
	
	my @msg = ( 'DATA', $counter, $encoded, $hash );
	
	return $socket->send (join ( ';', @msg ));
}

sub repeatSending {

}